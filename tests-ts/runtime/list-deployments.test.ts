import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { FlyctlAdapter } from "../../src/adapters/flyctl.ts";
import { NodeProcessRunner, type ProcessRunner } from "../../src/adapters/process.ts";
import { runListCommand } from "../../src/commands/list.ts";
import type { FlyctlPort } from "../../src/adapters/flyctl.ts";
import type { DeploymentListRow, DeploymentRegistryPort } from "../../src/contexts/runtime/application/ports/deployment-registry.port.ts";
import { ListDeploymentsUseCase } from "../../src/contexts/runtime/application/use-cases/list-deployments.ts";
import {
  FlyDeploymentRegistry,
  resolveConfigDir
} from "../../src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts";

describe("process adapter", () => {
  it("captures stdout, stderr, and exitCode with env overrides", async () => {
    const runner = new NodeProcessRunner();

    const result = await runner.run(
      process.execPath,
      [
        "-e",
        [
          "process.stdout.write((process.env.HERMES_MARKER || '') + '\\n')",
          "process.stderr.write('stderr-line\\n')",
          "process.exit(7)"
        ].join(";")
      ],
      {
        env: {
          HERMES_MARKER: "marker-value"
        }
      }
    );

    assert.equal(result.stdout, "marker-value\n");
    assert.equal(result.stderr, "stderr-line\n");
    assert.equal(result.exitCode, 7);
  });
});

describe("flyctl adapter", () => {
  it("parses the first machine from fly machine list json", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: JSON.stringify([
          { id: "machine123", state: "started", region: "fra" },
          { id: "machine456", state: "stopped", region: "ams" }
        ]),
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner, { HOME: "" });
    const machine = await adapter.getMachineSummary("test-app");
    const state = await adapter.getMachineState("test-app");

    assert.deepEqual(machine, { id: "machine123", state: "started", region: "fra" });
    assert.equal(state, "started");
  });

  it("falls back to fly status json when machine list parsing fails", async () => {
    let callCount = 0;
    const runner: ProcessRunner = {
      run: async () => {
        callCount += 1;
        if (callCount === 1) {
          return {
            stdout: "not-json",
            stderr: "",
            exitCode: 0
          };
        }

        return {
          stdout: JSON.stringify({
            Machines: [
              { ID: "machine789", state: "started", region: "ord" }
            ]
          }),
          stderr: "",
          exitCode: 0
        };
      }
    };

    const adapter = new FlyctlAdapter(runner, { HOME: "" });
    const machine = await adapter.getMachineSummary("test-app");

    assert.deepEqual(machine, { id: "machine789", state: "started", region: "ord" });
  });

  it("returns null on non-zero exit", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "failed",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner, { HOME: "" });
    const state = await adapter.getMachineState("test-app");

    assert.equal(state, null);
  });

  it("returns null on parse failure", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "not-json",
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner, { HOME: "" });
    const state = await adapter.getMachineState("test-app");

    assert.equal(state, null);
  });
});

describe("list deployments use-case", () => {
  it("returns empty-state result for empty registry", async () => {
    const registry: DeploymentRegistryPort = {
      listDeployments: async () => []
    };

    const useCase = new ListDeploymentsUseCase(registry);
    const result = await useCase.execute();

    assert.deepEqual(result, { kind: "empty" });
  });

  it("returns deterministic rows for non-empty registry", async () => {
    const rows: DeploymentListRow[] = [
      {
        appName: "app-b",
        region: "ord",
        platform: "-",
        machine: "machine123 (started)",
        telegramBot: "-",
        telegramLink: "-"
      },
      {
        appName: "app-a",
        region: "ams",
        platform: "telegram",
        machine: "machine456 (stopped)",
        telegramBot: "@testhermesbot",
        telegramLink: "https://t.me/testhermesbot"
      }
    ];

    const registry: DeploymentRegistryPort = {
      listDeployments: async () => rows
    };

    const useCase = new ListDeploymentsUseCase(registry);
    const result = await useCase.execute();

    assert.deepEqual(result, {
      kind: "rows",
      rows
    });
  });
});

describe("runListCommand", () => {
  it("prints machine and Telegram coordinates in the table", async () => {
    const stdoutChunks: string[] = [];
    const useCase = new ListDeploymentsUseCase({
      listDeployments: async () => [
        {
          appName: "test-app",
          region: "fra",
          platform: "telegram",
          machine: "machine123 (started)",
          telegramBot: "@testhermesbot",
          telegramLink: "https://t.me/testhermesbot"
        }
      ]
    });

    const code = await runListCommand({
      stdout: { write: (value: string) => { stdoutChunks.push(value); } },
      useCase
    });

    const output = stdoutChunks.join("");
    assert.equal(code, 0);
    assert.match(output, /Telegram Bot/);
    assert.match(output, /Telegram Link/);
    assert.match(output, /machine123 \(started\)/);
    assert.match(output, /@testhermesbot/);
    assert.match(output, /https:\/\/t\.me\/testhermesbot/);
  });
});

describe("flyctl adapter - installed fly fallback", () => {
  it("uses ~/.fly/bin/fly when it exists even if fly is not on PATH", async () => {
    const root = await mkdtemp(join(tmpdir(), "flyctl-home-fallback-"));
    const flyBinDir = join(root, ".fly", "bin");
    const flyPath = join(flyBinDir, "fly");
    const calls: Array<{ command: string; args: string[] }> = [];

    try {
      await mkdir(flyBinDir, { recursive: true });
      await writeFile(flyPath, "#!/bin/sh\nexit 0\n", "utf8");
      await chmod(flyPath, 0o755);

      const adapter = new FlyctlAdapter(
        {
          run: async (command, args) => {
            calls.push({ command, args });
            if (args[0] === "machine" && args[1] === "list") {
              return {
                stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
                stderr: "",
                exitCode: 0
              };
            }
            return { stdout: "", stderr: "", exitCode: 0 };
          }
        },
        { HOME: root }
      );

      const machine = await adapter.getMachineSummary("test-app");

      assert.deepEqual(machine, { id: "machine123", state: "started", region: "fra" });
      assert.equal(calls[0]?.command, flyPath);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("fly deployment registry", () => {
  it("normalizes dot-slash-prefixed HERMES_FLY_CONFIG_DIR to TS path semantics", () => {
    assert.equal(resolveConfigDir({ HERMES_FLY_CONFIG_DIR: "./tmp//nested//" }), "tmp/nested");
  });

  it("preserves order, truncates app names, and applies placeholder fallbacks", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-runtime-list-"));
    const configDir = join(root, "config");
    const deploysDir = join(configDir, "deploys");

    try {
      await mkdir(deploysDir, { recursive: true });

      const longApp = "my-extremely-long-hermes-agent-name";
      const secondApp = "test-app";

      await writeFile(
        join(configDir, "config.yaml"),
        [
          "apps:",
          `  - name: ${longApp}`,
          "    platform: telegram",
          "    telegram_bot_username: longhermesbot",
          "    deployed_at: 2026-03-12T00:00:00Z",
          `  - name: ${secondApp}`,
          "    region: ord",
          "    deployed_at: 2026-03-12T00:00:00Z",
          ""
        ].join("\n"),
        "utf8"
      );

      await writeFile(
        join(deploysDir, `${longApp}.yaml`),
        "messaging:\n  platform: telegram\n",
        "utf8"
      );

      const flyctl: FlyctlPort = {
        getMachineSummary: async (appName: string) => (
          appName === longApp
            ? { id: "machine123", state: "started", region: "ord" }
            : { id: null, state: null, region: null }
        ),
        getMachineState: async (appName: string) => (appName === longApp ? "started" : null),
        getTelegramBotIdentity: async (appName: string) => (
          appName === secondApp
            ? { configured: true, username: "secondbot", link: "https://t.me/secondbot" }
            : { configured: false, username: null, link: null }
        )
      };

      const registry = new FlyDeploymentRegistry({
        flyctl,
        env: {
          ...process.env,
          HERMES_FLY_CONFIG_DIR: configDir
        }
      });

      const rows = await registry.listDeployments();

      assert.deepEqual(rows, [
        {
          appName: "my-extremely-long-herme...",
          region: "?",
          platform: "telegram",
          machine: "machine123 (started)",
          telegramBot: "@longhermesbot",
          telegramLink: "https://t.me/longhermesbot"
        },
        {
          appName: "test-app",
          region: "ord",
          platform: "telegram",
          machine: "?",
          telegramBot: "@secondbot",
          telegramLink: "https://t.me/secondbot"
        }
      ]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("does not resolve config from relative .hermes-fly when HOME is empty", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-runtime-list-home-empty-"));
    const configDir = join(root, ".hermes-fly");
    const previousCwd = process.cwd();

    try {
      await mkdir(configDir, { recursive: true });
      await writeFile(
        join(configDir, "config.yaml"),
        ["apps:", "  - name: should-not-be-loaded", "    region: ord", ""].join("\n"),
        "utf8"
      );

      process.chdir(root);

      const flyctl: FlyctlPort = {
        getMachineSummary: async () => ({ id: "machine123", state: "started", region: "ord" }),
        getMachineState: async () => "started",
        getTelegramBotIdentity: async () => ({ configured: false, username: null, link: null })
      };

      const registry = new FlyDeploymentRegistry({
        flyctl,
        env: {
          HOME: ""
        }
      });

      const rows = await registry.listDeployments();
      assert.deepEqual(rows, []);
    } finally {
      process.chdir(previousCwd);
      await rm(root, { recursive: true, force: true });
    }
  });

  it("does not resolve config from relative .hermes-fly when HOME is unset", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-runtime-list-home-unset-"));
    const configDir = join(root, ".hermes-fly");
    const previousCwd = process.cwd();

    try {
      await mkdir(configDir, { recursive: true });
      await writeFile(
        join(configDir, "config.yaml"),
        ["apps:", "  - name: should-not-be-loaded", "    region: ord", ""].join("\n"),
        "utf8"
      );

      process.chdir(root);

      const flyctl: FlyctlPort = {
        getMachineSummary: async () => ({ id: "machine123", state: "started", region: "ord" }),
        getMachineState: async () => "started",
        getTelegramBotIdentity: async () => ({ configured: false, username: null, link: null })
      };

      const registry = new FlyDeploymentRegistry({
        flyctl,
        env: {}
      });

      const rows = await registry.listDeployments();
      assert.deepEqual(rows, []);
    } finally {
      process.chdir(previousCwd);
      await rm(root, { recursive: true, force: true });
    }
  });
});
