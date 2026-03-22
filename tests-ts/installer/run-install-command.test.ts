import assert from "node:assert/strict";
import test from "node:test";
import { runInstallCommand } from "../../src/install-cli.ts";
import type { InstallerBootstrapPort } from "../../src/contexts/installer/application/ports/installer-shell.port.ts";
import type { InstallerPlan } from "../../src/contexts/installer/domain/install-plan.ts";
import { HERMES_FLY_TS_VERSION } from "../../src/version.ts";

const CURRENT_RELEASE_REF = `v${HERMES_FLY_TS_VERSION}`;

function createShell(overrides: Partial<InstallerBootstrapPort> = {}): InstallerBootstrapPort {
  return {
    readCommandVersion: async (command) => (command === "node" ? process.version : "11.11.1"),
    readCommandPath: async (command) => (command === "node" ? process.execPath : "/usr/bin/npm"),
    resolveExistingInstall: async () => null,
    requiresSudo: async () => false,
    installFiles: async () => undefined,
    verifyInstalledVersion: async () => undefined,
    readInstalledVersion: async () => `hermes-fly ${HERMES_FLY_TS_VERSION}`,
    resolveInstallRef: async () => CURRENT_RELEASE_REF,
    prepareInstallSource: async () => ({
      sourceDir: "/tmp/hermes-fly",
      installMethod: "release_asset",
      cleanup: () => undefined,
    }),
    ensureRuntimeArtifacts: async () => undefined,
    ...overrides,
  };
}

test("runInstallCommand resolves the install ref and builds an InstallerPlan", async () => {
  const calls: InstallerPlan[] = [];
  const shell = createShell();

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
      installHome: "/usr/local/lib/hermes-fly",
      binDir: "/usr/local/bin",
    },
    shell,
    async (plan) => {
      calls.push(plan);
      return 0;
    },
  );

  assert.equal(code, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.installRef, CURRENT_RELEASE_REF);
  assert.equal(calls[0]?.installMethod, "release_asset");
  assert.equal(calls[0]?.sourceDir, "/tmp/hermes-fly");
});

test("runInstallCommand honors an explicit install ref without asking the shell to resolve one", async () => {
  let resolved = false;

  const shell = createShell({
    resolveInstallRef: async () => {
      resolved = true;
      return "v9.9.9";
    },
  });

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
      installRef: "v0.1.50",
      installHome: "/usr/local/lib/hermes-fly",
      binDir: "/usr/local/bin",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installRef, "v0.1.50");
      return 0;
    },
  );

  assert.equal(code, 0);
  assert.equal(resolved, false);
});

test("runInstallCommand resolves channel and version from the injected env context", async () => {
  const resolveInstallRefCalls: Array<{ channel: string; version?: string }> = [];
  const shell = createShell({
    resolveInstallRef: async (channel, version) => {
      resolveInstallRefCalls.push({ channel, version });
      return "v0.1.77";
    },
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installChannel, "preview");
      assert.equal(plan.installRef, "v0.1.77");
      return 0;
    },
    {
      env: {
        HERMES_FLY_CHANNEL: "preview",
        HERMES_FLY_VERSION: "0.1.77",
      },
      homeDir: "/home/sprite",
    },
  );

  assert.equal(code, 0);
  assert.deepEqual(resolveInstallRefCalls, [{
    channel: "preview",
    version: "0.1.77",
  }]);
});

test("runInstallCommand uses platform defaults when install locations are omitted", async () => {
  const shell = createShell();

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/home/sprite/.local/share/hermes-fly");
      assert.equal(plan.binDir, "/home/sprite/.local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/home/sprite",
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand honors HOME from the injected env when deriving default install paths", async () => {
  const shell = createShell();

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/tmp/ci-home/Library/Application Support/hermes-fly");
      assert.equal(plan.binDir, "/tmp/ci-home/.local/bin");
      return 0;
    },
    {
      env: {
        HOME: "/tmp/ci-home",
      },
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand resolves existing installs with privileged preferences", async () => {
  let resolvedOptions:
    | {
      platform?: string;
      homeDir?: string;
      xdgDataHome?: string;
      preferSystemInstall?: boolean;
    }
    | undefined;
  const shell = createShell({
    resolveExistingInstall: async (options) => {
      resolvedOptions = options;
      return null;
    },
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async () => 0,
    {
      env: {
        XDG_DATA_HOME: "/srv/alice-xdg",
      },
      homeDir: "/root",
      userId: 0,
    },
  );

  assert.equal(code, 0);
  assert.deepEqual(resolvedOptions, {
    platform: "linux",
    homeDir: "/root",
    xdgDataHome: "/srv/alice-xdg",
    preferSystemInstall: true,
  });
});

test("runInstallCommand preserves an existing install when no overrides are provided", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/usr/local/lib/hermes-fly",
      binDir: "/usr/local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
      assert.equal(plan.binDir, "/usr/local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/Users/alex",
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand ignores existing install paths when a partial override is provided", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/usr/local/lib/hermes-fly",
      binDir: "/usr/local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
      installHome: "/Users/alex/custom/hermes-fly",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/Users/alex/custom/hermes-fly");
      assert.equal(plan.binDir, "/Users/alex/.local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/Users/alex",
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand treats HERMES_FLY_HOME as an install-home override in the bootstrap flow", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/usr/local/lib/hermes-fly",
      binDir: "/usr/local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/Users/alex/custom-hermes-home");
      assert.equal(plan.binDir, "/Users/alex/.local/bin");
      return 0;
    },
    {
      env: {
        HERMES_FLY_HOME: "/Users/alex/custom-hermes-home",
      },
      homeDir: "/Users/alex",
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand ignores inherited HERMES_HOME when HERMES_FLY_HOME is unset", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => null,
  });

  const code = await runInstallCommand(
    {
      platform: "darwin",
      arch: "arm64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/Users/alex/Library/Application Support/hermes-fly");
      assert.equal(plan.binDir, "/Users/alex/.local/bin");
      return 0;
    },
    {
      env: {
        HERMES_HOME: "/Users/alex/.hermes",
      },
      homeDir: "/Users/alex",
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand uses the system layout for fresh root installs", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => null,
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
      assert.equal(plan.binDir, "/usr/local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/root",
      userId: 0,
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand keeps system defaults for the missing side of a root partial override", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => null,
  });

  const installHomeOverrideCode = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
      installHome: "/opt/hermes-fly",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/opt/hermes-fly");
      assert.equal(plan.binDir, "/usr/local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/root",
      userId: 0,
    },
  );

  assert.equal(installHomeOverrideCode, 0);

  const binDirOverrideCode = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
      binDir: "/opt/hermes-bin",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
      assert.equal(plan.binDir, "/opt/hermes-bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/root",
      userId: 0,
    },
  );

  assert.equal(binDirOverrideCode, 0);
});

test("runInstallCommand does not reuse a user-local existing layout during a root install", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/home/alice/.local/lib/hermes-fly",
      binDir: "/home/alice/.local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
      assert.equal(plan.binDir, "/usr/local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/home/alice",
      userId: 0,
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand does not reuse an existing XDG_DATA_HOME layout during a root install", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/home/alice/.xdg/data/hermes-fly",
      binDir: "/home/alice/.local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
      assert.equal(plan.binDir, "/usr/local/bin");
      return 0;
    },
    {
      env: {
        XDG_DATA_HOME: "/home/alice/.xdg/data",
      },
      homeDir: "/home/alice",
      userId: 0,
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand still reuses a staged .local prefix during a root install", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/opt/stage/.local/share/hermes-fly",
      binDir: "/opt/stage/.local/bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/opt/stage/.local/share/hermes-fly");
      assert.equal(plan.binDir, "/opt/stage/.local/bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/home/alice",
      userId: 0,
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand reuses a custom existing layout during a root install", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => ({
      installHome: "/opt/hermes-fly",
      binDir: "/opt/hermes-bin",
    }),
  });

  const code = await runInstallCommand(
    {
      platform: "linux",
      arch: "amd64",
      installChannel: "latest",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/opt/hermes-fly");
      assert.equal(plan.binDir, "/opt/hermes-bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/root",
      userId: 0,
    },
  );

  assert.equal(code, 0);
});

test("runInstallCommand accepts fully explicit destinations without resolving unsupported platform defaults", async () => {
  const shell = createShell({
    resolveExistingInstall: async () => null,
  });

  const code = await runInstallCommand(
    {
      platform: "freebsd",
      arch: "amd64",
      installChannel: "latest",
      installHome: "/opt/hermes-fly",
      binDir: "/opt/hermes-bin",
    },
    shell,
    async (plan) => {
      assert.equal(plan.installHome, "/opt/hermes-fly");
      assert.equal(plan.binDir, "/opt/hermes-bin");
      return 0;
    },
    {
      env: {},
      homeDir: "/tmp/ignored",
    },
  );

  assert.equal(code, 0);
});
