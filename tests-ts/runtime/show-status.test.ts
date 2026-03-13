import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { resolveConfigDir, isSafeAppName } from "../../src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts";
import { readCurrentApp } from "../../src/contexts/runtime/infrastructure/adapters/current-app-config.ts";
import { resolveApp } from "../../src/commands/resolve-app.ts";

// ---------------------------------------------------------------
// resolve-app parity
// ---------------------------------------------------------------

describe("resolve-app", () => {
  it("-a APP wins over current app", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a", "explicit-app"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "explicit-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("current app is used when -a is absent", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp([], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "fallback-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("unrelated args are ignored", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["--unknown-flag", "--json"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "fallback-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("-a without a value falls back to current app", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "fallback-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("unresolved app returns null", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const app = await resolveApp([], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("repeated -a uses last value", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-resolve-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const app = await resolveApp(["-a", "first-app", "-a", "last-app"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "last-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------
// current-app-config parity
// ---------------------------------------------------------------

describe("current-app-config", () => {
  it("returns current_app value from config.yaml", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-current-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: test-app\n",
        "utf8"
      );
      const app = await readCurrentApp({ env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") } });
      assert.equal(app, "test-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns null when config file is missing", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-current-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const app = await readCurrentApp({ env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") } });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns null when current_app is missing from config", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-current-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "apps:\n  - name: test-app\n",
        "utf8"
      );
      const app = await readCurrentApp({ env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") } });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns null when current_app is empty", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-current-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: \n",
        "utf8"
      );
      const app = await readCurrentApp({ env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") } });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns null when current_app fails validation (bad chars)", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-current-app-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: bad name\n",
        "utf8"
      );
      const app = await readCurrentApp({ env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") } });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------
// fly-deployment-registry exports
// ---------------------------------------------------------------

describe("fly-deployment-registry exports", () => {
  it("exports resolveConfigDir", () => {
    assert.equal(typeof resolveConfigDir, "function");
  });

  it("exports isSafeAppName", () => {
    assert.equal(typeof isSafeAppName, "function");
    assert.equal(isSafeAppName("valid-app"), true);
    assert.equal(isSafeAppName("bad name"), false);
    assert.equal(isSafeAppName(""), false);
  });
});

// ---------------------------------------------------------------
// flyctl adapter: getAppStatus and getAppLogs
// ---------------------------------------------------------------

import { FlyctlAdapter } from "../../src/adapters/flyctl.ts";
import type { ProcessRunner } from "../../src/adapters/process.ts";
import type { StatusReaderPort } from "../../src/contexts/runtime/application/ports/status-reader.port.ts";
import { ShowStatusUseCase } from "../../src/contexts/runtime/application/use-cases/show-status.ts";
import { FlyStatusReader } from "../../src/contexts/runtime/infrastructure/adapters/fly-status-reader.ts";
import { runStatusCommand } from "../../src/commands/status.ts";

describe("FlyctlAdapter.getAppStatus", () => {
  it("returns ok result with parsed fields from fly status --json", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: JSON.stringify({
          app: {
            name: "test-app",
            status: "started",
            hostname: "test-app.fly.dev"
          },
          machines: [
            { state: "started", region: "ord" }
          ]
        }),
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppStatus("test-app");

    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.appName, "test-app");
      assert.equal(result.status, "started");
      assert.equal(result.hostname, "test-app.fly.dev");
      assert.equal(result.machineState, "started");
      assert.equal(result.region, "ord");
    }
  });

  it("returns ok: false with stderr on non-zero exit", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "Error: app not found",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppStatus("bad-app");

    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.error, "Error: app not found");
    }
  });

  it("returns ok: false with stdout fallback when stderr empty", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "some error output",
        stderr: "",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppStatus("bad-app");

    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.error, "some error output");
    }
  });

  it("returns ok: false with 'unknown error' when both stdout and stderr empty", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppStatus("bad-app");

    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.error, "unknown error");
    }
  });

  it("returns ok: false on JSON parse failure", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "not-json",
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppStatus("test-app");

    assert.equal(result.ok, false);
  });
});

// ---------------------------------------------------------------
// ShowStatusUseCase
// ---------------------------------------------------------------

describe("ShowStatusUseCase", () => {
  it("returns ok with correct fields from reader", async () => {
    const reader: StatusReaderPort = {
      getStatus: async (appName: string) => ({
        kind: "ok" as const,
        details: {
          appName,
          status: "started",
          machine: "started",
          region: "ord",
          hostname: "test-app.fly.dev"
        }
      })
    };

    const useCase = new ShowStatusUseCase(reader);
    const result = await useCase.execute("test-app");

    assert.equal(result.kind, "ok");
    if (result.kind === "ok") {
      assert.equal(result.details.appName, "test-app");
      assert.equal(result.details.status, "started");
      assert.equal(result.details.machine, "started");
      assert.equal(result.details.region, "ord");
      assert.equal(result.details.hostname, "test-app.fly.dev");
    }
  });

  it("returns error from reader failure", async () => {
    const reader: StatusReaderPort = {
      getStatus: async () => ({
        kind: "error" as const,
        message: "Error: app not found"
      })
    };

    const useCase = new ShowStatusUseCase(reader);
    const result = await useCase.execute("bad-app");

    assert.equal(result.kind, "error");
    if (result.kind === "error") {
      assert.equal(result.message, "Error: app not found");
    }
  });
});

// ---------------------------------------------------------------
// FlyStatusReader placeholder mappings
// ---------------------------------------------------------------

describe("FlyStatusReader", () => {
  it("maps missing fields to unknown placeholders", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: JSON.stringify({
          app: { name: "test-app" },
          machines: []
        }),
        stderr: "",
        exitCode: 0
      })
    };
    const adapter = new FlyctlAdapter(runner);
    const reader = new FlyStatusReader(adapter);
    const result = await reader.getStatus("test-app");

    assert.equal(result.kind, "ok");
    if (result.kind === "ok") {
      assert.equal(result.details.status, "unknown");
      assert.equal(result.details.machine, "unknown");
      assert.equal(result.details.region, "unknown");
      assert.equal(result.details.hostname, null);
    }
  });

  it("preserves exact error string from flyctl on failure", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "Error: app not found",
        exitCode: 1
      })
    };
    const adapter = new FlyctlAdapter(runner);
    const reader = new FlyStatusReader(adapter);
    const result = await reader.getStatus("bad-app");

    assert.equal(result.kind, "error");
    if (result.kind === "error") {
      assert.equal(result.message, "Error: app not found");
    }
  });
});

// ---------------------------------------------------------------
// runStatusCommand
// ---------------------------------------------------------------

describe("runStatusCommand", () => {
  it("writes formatted status lines to stderr and returns 0 on success", async () => {
    const reader: StatusReaderPort = {
      getStatus: async (appName: string) => ({
        kind: "ok" as const,
        details: {
          appName,
          status: "started",
          machine: "started",
          region: "ord",
          hostname: "test-app.fly.dev"
        }
      })
    };

    const errLines: string[] = [];
    const stderr = { write: (s: string) => { errLines.push(s); } };
    const outChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };

    const code = await runStatusCommand(["-a", "test-app"], {
      useCase: new ShowStatusUseCase(reader),
      stderr,
      stdout
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "");
    const errOut = errLines.join("");
    assert.ok(errOut.includes("[info] App:     test-app"));
    assert.ok(errOut.includes("[info] Status:  started"));
    assert.ok(errOut.includes("[info] Machine: started"));
    assert.ok(errOut.includes("[info] Region:  ord"));
    assert.ok(errOut.includes("✓ URL:     https://test-app.fly.dev"));
  });

  it("omits URL line when hostname is null", async () => {
    const reader: StatusReaderPort = {
      getStatus: async (appName: string) => ({
        kind: "ok" as const,
        details: {
          appName,
          status: "started",
          machine: "started",
          region: "ord",
          hostname: null
        }
      })
    };

    const errLines: string[] = [];
    const stderr = { write: (s: string) => { errLines.push(s); } };
    const stdout = { write: () => {} };

    const code = await runStatusCommand(["-a", "test-app"], {
      useCase: new ShowStatusUseCase(reader),
      stderr,
      stdout
    });

    assert.equal(code, 0);
    const errOut = errLines.join("");
    assert.ok(!errOut.includes("✓ URL:"));
  });

  it("writes no-app error to stderr and returns 1 when no app resolved", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-status-noapp-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const errLines: string[] = [];
      const stderr = { write: (s: string) => { errLines.push(s); } };
      const outChunks: string[] = [];
      const stdout = { write: (s: string) => { outChunks.push(s); } };

      const reader: StatusReaderPort = {
        getStatus: async () => ({ kind: "ok" as const, details: { appName: "x", status: null, machine: null, region: null, hostname: null } })
      };

      const code = await runStatusCommand([], {
        useCase: new ShowStatusUseCase(reader),
        stderr,
        stdout,
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });

      assert.equal(code, 1);
      assert.equal(outChunks.join(""), "");
      assert.equal(errLines.join(""), "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("writes failure error to stderr and returns 1 on fly failure", async () => {
    const reader: StatusReaderPort = {
      getStatus: async () => ({
        kind: "error" as const,
        message: "Error: app not found"
      })
    };

    const errLines: string[] = [];
    const stderr = { write: (s: string) => { errLines.push(s); } };
    const outChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };

    const code = await runStatusCommand(["-a", "bad-app"], {
      useCase: new ShowStatusUseCase(reader),
      stderr,
      stdout
    });

    assert.equal(code, 1);
    assert.equal(outChunks.join(""), "");
    assert.equal(errLines.join(""), "[error] Failed to get status for app 'bad-app': Error: app not found\n");
  });
});

describe("FlyctlAdapter.getAppLogs", () => {
  it("returns raw stdout, stderr, and exitCode without modification", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "2024-01-15T10:00:00Z [info] Hermes gateway started\n",
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppLogs("test-app");

    assert.equal(result.stdout, "2024-01-15T10:00:00Z [info] Hermes gateway started\n");
    assert.equal(result.stderr, "");
    assert.equal(result.exitCode, 0);
  });

  it("returns non-zero exitCode and raw stderr on failure", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "Error: app not found\n",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const result = await adapter.getAppLogs("bad-app");

    assert.equal(result.exitCode, 1);
    assert.equal(result.stderr, "Error: app not found\n");
  });
});
