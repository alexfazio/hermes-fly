import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { FlyctlAdapter } from "../../src/adapters/flyctl.ts";
import { NodeProcessRunner, type ProcessRunner } from "../../src/adapters/process.ts";
import type { FlyctlPort } from "../../src/adapters/flyctl.ts";
import type { DeploymentListRow, DeploymentRegistryPort } from "../../src/contexts/runtime/application/ports/deployment-registry.port.ts";
import { ListDeploymentsUseCase } from "../../src/contexts/runtime/application/use-cases/list-deployments.ts";
import { FlyDeploymentRegistry } from "../../src/contexts/runtime/infrastructure/adapters/fly-deployment-registry.ts";

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
  it("parses first machine state from fly status json", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: JSON.stringify({
          Machines: [
            { state: "started" },
            { state: "stopped" }
          ]
        }),
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const state = await adapter.getMachineState("test-app");

    assert.equal(state, "started");
  });

  it("returns null on non-zero exit", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "",
        stderr: "failed",
        exitCode: 1
      })
    };

    const adapter = new FlyctlAdapter(runner);
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

    const adapter = new FlyctlAdapter(runner);
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
        machine: "started"
      },
      {
        appName: "app-a",
        region: "ams",
        platform: "telegram",
        machine: "stopped"
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

describe("fly deployment registry", () => {
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
        getMachineState: async (appName: string) => (appName === longApp ? "started" : null)
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
          machine: "started"
        },
        {
          appName: "test-app",
          region: "ord",
          platform: "-",
          machine: "?"
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
        getMachineState: async () => "started"
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
});
