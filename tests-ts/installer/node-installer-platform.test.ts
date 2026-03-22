import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ProcessRunner } from "../../src/adapters/process.ts";
import { InstallerPlan } from "../../src/contexts/installer/domain/install-plan.ts";
import { NodeInstallerPlatform } from "../../src/contexts/installer/infrastructure/adapters/node-installer-platform.ts";

test("NodeInstallerPlatform does not require sudo for nested user-local paths under a writable home", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-home-"));
  const platform = new NodeInstallerPlatform();

  try {
    const needsSudo = await platform.requiresSudo(
      join(homeDir, "Library", "Application Support", "hermes-fly"),
      join(homeDir, ".local", "bin"),
    );

    assert.equal(needsSudo, false);
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform builds the no-sudo hint from the active HOME and XDG_DATA_HOME", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-nosudo-hint-"));
  const lockedRoot = join(rootDir, "locked-root");
  mkdirSync(lockedRoot, { recursive: true });
  chmodSync(lockedRoot, 0o555);

  const plan = InstallerPlan.create({
    platform: "linux",
    arch: "amd64",
    installChannel: "latest",
    installMethod: "release_asset",
    installRef: "v0.1.99",
    installHome: join(lockedRoot, "hermes-fly"),
    binDir: join(lockedRoot, "bin"),
    sourceDir: join(rootDir, "source"),
  });

  const runner: ProcessRunner = {
    run: async () => ({
      stdout: "",
      stderr: "",
      exitCode: 1,
    }),
    runStreaming: async () => ({ exitCode: 0 }),
  };

  const platform = new NodeInstallerPlatform(runner, {
    HOME: join(rootDir, "ci-home"),
    XDG_DATA_HOME: join(rootDir, "ci-xdg", "data"),
    PATH: "",
  });

  try {
    await assert.rejects(
      async () => await platform.installFiles(plan),
      /Try: HERMES_FLY_INSTALL_DIR=".*ci-home\/.local\/bin" HERMES_FLY_HOME=".*ci-xdg\/data\/hermes-fly" bash install\.sh/,
    );
  } finally {
    chmodSync(lockedRoot, 0o755);
    rmSync(rootDir, { recursive: true, force: true });
  }
});

function createRunner(commandPath: string): ProcessRunner {
  return {
    run: async () => ({
      stdout: `${commandPath}\n`,
      stderr: "",
      exitCode: 0,
    }),
    runStreaming: async () => ({ exitCode: 0 }),
  };
}

function createLookupRunner(commandPath: string | null): ProcessRunner {
  return {
    run: async (command, args) => {
      if (command === "/bin/bash" && args.join(" ") === "-lc type -P hermes-fly") {
        if (!commandPath) {
          return {
            stdout: "",
            stderr: "",
            exitCode: 1,
          };
        }
        return {
          stdout: `${commandPath}\n`,
          stderr: "",
          exitCode: 0,
        };
      }

      return {
        stdout: "",
        stderr: "",
        exitCode: 1,
      };
    },
    runStreaming: async () => ({ exitCode: 0 }),
  };
}

test("NodeInstallerPlatform ignores repo-like PATH targets without an installer marker", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-repo-"));
  const repoDir = join(rootDir, "repo");
  const binDir = join(rootDir, "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(repoDir, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(repoDir, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(repoDir, "dist", "cli.js"), "console.log('repo build');\n");
  writeFileSync(join(repoDir, "tsconfig.json"), "{}\n");
  mkdirSync(join(repoDir, "src"), { recursive: true });
  symlinkSync(join(repoDir, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createRunner(launcherPath),
    { HOME: rootDir, PATH: binDir },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.equal(existing, null);
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform falls back to a known managed install when PATH resolves to an unmanaged launcher", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-shadowed-"));
  const repoDir = join(rootDir, "repo");
  const repoBinDir = join(rootDir, "repo-bin");
  const repoLauncherPath = join(repoBinDir, "hermes-fly");
  const installHome = join(rootDir, ".local", "lib", "hermes-fly");
  const binDir = join(rootDir, ".local", "bin");
  const managedLauncherPath = join(binDir, "hermes-fly");

  mkdirSync(join(repoDir, "dist"), { recursive: true });
  mkdirSync(join(repoDir, "src"), { recursive: true });
  mkdirSync(repoBinDir, { recursive: true });
  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(repoDir, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(repoDir, "dist", "cli.js"), "console.log('repo build');\n");
  writeFileSync(join(repoDir, "tsconfig.json"), "{}\n");
  symlinkSync(join(repoDir, "hermes-fly"), repoLauncherPath);
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  symlinkSync(join(installHome, "hermes-fly"), managedLauncherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(repoLauncherPath),
    { HOME: rootDir, PATH: `${repoBinDir}:${binDir}` },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform preserves a known managed install when its launcher is missing", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-missing-known-launcher-"));
  const installHome = join(rootDir, ".local", "lib", "hermes-fly");
  const binDir = join(rootDir, ".local", "bin");
  const expectedBinDir = realpathSync(rootDir) + "/.local/bin";

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");

  const platform = new NodeInstallerPlatform(
    createRunner("/usr/bin/hermes-fly"),
    { HOME: rootDir, PATH: "/usr/bin:/bin" },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: expectedBinDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform preserves a known managed install when its launcher is replaced", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-replaced-known-launcher-"));
  const installHome = join(rootDir, ".local", "lib", "hermes-fly");
  const binDir = join(rootDir, ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");
  const expectedBinDir = realpathSync(rootDir) + "/.local/bin";

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(launcherPath, "#!/bin/sh\necho shadowed\n");

  const platform = new NodeInstallerPlatform(
    createRunner(launcherPath),
    { HOME: rootDir, PATH: binDir },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: expectedBinDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform preserves a marked custom install later on PATH after an unmanaged hit", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-custom-path-"));
  const repoDir = join(rootDir, "repo");
  const repoBinDir = join(rootDir, "repo-bin");
  const repoLauncherPath = join(repoBinDir, "hermes-fly");
  const installHome = join(rootDir, "custom-install-home");
  const binDir = join(rootDir, "custom-bin");
  const managedLauncherPath = join(binDir, "hermes-fly");

  mkdirSync(join(repoDir, "dist"), { recursive: true });
  mkdirSync(join(repoDir, "src"), { recursive: true });
  mkdirSync(repoBinDir, { recursive: true });
  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(repoDir, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(repoDir, "dist", "cli.js"), "console.log('repo build');\n");
  writeFileSync(join(repoDir, "tsconfig.json"), "{}\n");
  symlinkSync(join(repoDir, "hermes-fly"), repoLauncherPath);
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), managedLauncherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(repoLauncherPath),
    {
      HOME: rootDir,
      PATH: `${repoBinDir}:${binDir}`,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform keeps scanning after a user-local PATH hit is rejected for a privileged install", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-root-mixed-path-"));
  const userInstallHome = join(rootDir, ".local", "lib", "hermes-fly");
  const userBinDir = join(rootDir, ".local", "bin");
  const customInstallHome = join(rootDir, "custom-install-home");
  const customBinDir = join(rootDir, "custom-bin");

  mkdirSync(join(userInstallHome, "dist"), { recursive: true });
  mkdirSync(userBinDir, { recursive: true });
  mkdirSync(join(customInstallHome, "dist"), { recursive: true });
  mkdirSync(customBinDir, { recursive: true });
  writeFileSync(join(userInstallHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(userInstallHome, "dist", "cli.js"), "console.log('user-local');\n");
  writeFileSync(join(userInstallHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(userInstallHome, "hermes-fly"), join(userBinDir, "hermes-fly"));
  writeFileSync(join(customInstallHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(customInstallHome, "dist", "cli.js"), "console.log('custom');\n");
  writeFileSync(join(customInstallHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(customInstallHome, "hermes-fly"), join(customBinDir, "hermes-fly"));

  const platform = new NodeInstallerPlatform(
    createRunner(join(userBinDir, "hermes-fly")),
    {
      HOME: rootDir,
      PATH: `${userBinDir}:${customBinDir}`,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall({
      platform: "linux",
      homeDir: rootDir,
      preferSystemInstall: true,
    });
    assert.deepEqual(existing, {
      installHome: realpathSync(customInstallHome),
      binDir: customBinDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform still reuses a staged .local prefix during a privileged install", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-root-staged-local-"));
  const installHome = join(rootDir, "stage", ".local", "share", "hermes-fly");
  const binDir = join(rootDir, "stage", ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('staged');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createRunner(launcherPath),
    {
      HOME: join(rootDir, "active-home"),
      PATH: binDir,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall({
      platform: "linux",
      homeDir: join(rootDir, "active-home"),
      preferSystemInstall: true,
    });
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform accepts PATH targets marked as installer-managed", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-managed-"));
  const installHome = join(rootDir, "install-home");
  const binDir = join(rootDir, "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(createRunner(launcherPath), {
    HOME: rootDir,
    PATH: binDir,
  });

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform accepts pre-marker user-local installs from the historical no-sudo layout", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-user-local-"));
  const installHome = join(homeDir, ".local", "lib", "hermes-fly");
  const binDir = join(homeDir, ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(launcherPath),
    {
      HOME: homeDir,
      PATH: binDir,
    },
    {
      systemInstallHome: join(homeDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(homeDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform accepts legacy lib-based installs from the historical system layout", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-legacy-lib-system-"));
  const systemRoot = join(rootDir, "legacy-system");
  const installHome = join(systemRoot, "lib", "hermes-fly");
  const binDir = join(systemRoot, "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "lib"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "lib", "ui.sh"), "echo legacy\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(launcherPath),
    {
      HOME: join(rootDir, "unrelated-home"),
      PATH: binDir,
    },
    {
      systemInstallHome: installHome,
      systemBinDir: binDir,
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform accepts pre-marker custom installs that older installers created", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-pre-marker-custom-"));
  const installHome = join(rootDir, "custom-install-home");
  const binDir = join(rootDir, "custom-bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(join(installHome, "node_modules", "commander"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, "package.json"), "{\"name\":\"hermes-fly\"}\n");
  writeFileSync(join(installHome, "package-lock.json"), "{\"lockfileVersion\":3}\n");
  writeFileSync(join(installHome, "node_modules", "commander", "package.json"), "{\"name\":\"commander\"}\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(launcherPath),
    {
      HOME: rootDir,
      PATH: binDir,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform falls back to known managed locations when PATH has no hermes-fly launcher", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-known-location-"));
  const installHome = join(homeDir, ".local", "lib", "hermes-fly");
  const binDir = join(homeDir, ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(createLookupRunner(null), {
    HOME: homeDir,
    PATH: "/usr/bin:/bin",
  });

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: realpathSync(binDir),
    });
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform falls back to the XDG user-local install home when PATH has no hermes-fly launcher", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-xdg-location-"));
  const xdgDataHome = join(homeDir, ".xdg", "data");
  const installHome = join(xdgDataHome, "hermes-fly");
  const binDir = join(homeDir, ".local", "bin");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");

  const platform = new NodeInstallerPlatform(
    createLookupRunner(null),
    {
      HOME: homeDir,
      PATH: "/usr/bin:/bin",
      XDG_DATA_HOME: xdgDataHome,
    },
    {
      userInstallHome: join(xdgDataHome, "hermes-fly"),
      systemInstallHome: join(homeDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(homeDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: realpathSync(binDir),
    });
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform falls back to the known user bin launcher when PATH omits hermes-fly", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-known-bin-launcher-"));
  const installHome = join(homeDir, "custom-xdg-home", "hermes-fly");
  const binDir = join(homeDir, ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(null),
    {
      HOME: homeDir,
      PATH: "/usr/bin:/bin",
    },
    {
      systemInstallHome: join(homeDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(homeDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: realpathSync(binDir),
    });
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform ignores extra PATH shims when resolving a marked install bin dir", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-shim-path-"));
  const installHome = join(rootDir, "custom-install-home");
  const binDir = join(rootDir, "custom-bin");
  const shimBinDir = join(rootDir, "shim-bin");
  const managedLauncherPath = join(binDir, "hermes-fly");
  const shimLauncherPath = join(shimBinDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  mkdirSync(shimBinDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), managedLauncherPath);
  symlinkSync(managedLauncherPath, shimLauncherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(shimLauncherPath),
    {
      HOME: rootDir,
      PATH: `${shimBinDir}:${binDir}`,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform preserves a symlinked PATH directory when resolving an existing install", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-symlinked-path-dir-"));
  const installHome = join(rootDir, "custom-install-home");
  const canonicalBinDir = join(rootDir, "custom-bin");
  const pathAliasDir = join(rootDir, "path-alias");
  const launcherPath = join(pathAliasDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(join(installHome, "node_modules", "commander"), { recursive: true });
  mkdirSync(canonicalBinDir, { recursive: true });
  symlinkSync(canonicalBinDir, pathAliasDir);
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, "package.json"), "{\"name\":\"hermes-fly\"}\n");
  writeFileSync(join(installHome, "package-lock.json"), "{\"lockfileVersion\":3}\n");
  writeFileSync(join(installHome, "node_modules", "commander", "package.json"), "{\"name\":\"commander\"}\n");
  symlinkSync(join(installHome, "hermes-fly"), join(canonicalBinDir, "hermes-fly"));

  const platform = new NodeInstallerPlatform(
    createLookupRunner(launcherPath),
    {
      HOME: rootDir,
      PATH: pathAliasDir,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir: pathAliasDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform ignores repo checkouts in known managed legacy locations", async () => {
  const homeDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-repo-legacy-"));
  const installHome = join(homeDir, ".local", "lib", "hermes-fly");
  const binDir = join(homeDir, ".local", "bin");
  const launcherPath = join(binDir, "hermes-fly");

  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(join(installHome, "src"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('repo build');\n");
  writeFileSync(join(installHome, "tsconfig.json"), "{}\n");
  writeFileSync(join(installHome, "package.json"), "{\"name\":\"hermes-fly\"}\n");
  writeFileSync(join(installHome, "package-lock.json"), "{\"lockfileVersion\":3}\n");
  symlinkSync(join(installHome, "hermes-fly"), launcherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(launcherPath),
    {
      HOME: homeDir,
      PATH: binDir,
    },
    {
      systemInstallHome: join(homeDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(homeDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.equal(existing, null);
  } finally {
    rmSync(homeDir, { recursive: true, force: true });
  }
});

test("NodeInstallerPlatform skips cyclic launcher symlinks and continues scanning PATH", async () => {
  const rootDir = mkdtempSync(join(tmpdir(), "hermes-fly-installer-cyclic-path-"));
  const cycleABinDir = join(rootDir, "cycle-a");
  const cycleBBinDir = join(rootDir, "cycle-b");
  const cycleALauncherPath = join(cycleABinDir, "hermes-fly");
  const cycleBLauncherPath = join(cycleBBinDir, "hermes-fly");
  const installHome = join(rootDir, "custom-install-home");
  const binDir = join(rootDir, "custom-bin");
  const managedLauncherPath = join(binDir, "hermes-fly");

  mkdirSync(cycleABinDir, { recursive: true });
  mkdirSync(cycleBBinDir, { recursive: true });
  mkdirSync(join(installHome, "dist"), { recursive: true });
  mkdirSync(binDir, { recursive: true });
  symlinkSync(cycleBLauncherPath, cycleALauncherPath);
  symlinkSync(cycleALauncherPath, cycleBLauncherPath);
  writeFileSync(join(installHome, "hermes-fly"), "#!/bin/sh\nexit 0\n");
  writeFileSync(join(installHome, "dist", "cli.js"), "console.log('installed');\n");
  writeFileSync(join(installHome, ".hermes-fly-install-managed"), "1\n");
  symlinkSync(join(installHome, "hermes-fly"), managedLauncherPath);

  const platform = new NodeInstallerPlatform(
    createLookupRunner(cycleALauncherPath),
    {
      HOME: rootDir,
      PATH: `${cycleABinDir}:${binDir}`,
    },
    {
      systemInstallHome: join(rootDir, "missing-system", "lib", "hermes-fly"),
      systemBinDir: join(rootDir, "missing-system", "bin"),
    },
  );

  try {
    const existing = await platform.resolveExistingInstall();
    assert.deepEqual(existing, {
      installHome: realpathSync(installHome),
      binDir,
    });
  } finally {
    rmSync(rootDir, { recursive: true, force: true });
  }
});
