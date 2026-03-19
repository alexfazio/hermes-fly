import assert from "node:assert/strict";
import test from "node:test";
import { runInstallCommand } from "../../src/install-cli.ts";
import type { InstallerBootstrapPort } from "../../src/contexts/installer/application/ports/installer-shell.port.ts";
import type { InstallerPlan } from "../../src/contexts/installer/domain/install-plan.ts";

function createShell(overrides: Partial<InstallerBootstrapPort> = {}): InstallerBootstrapPort {
  return {
    readCommandVersion: async (command) => (command === "node" ? process.version : "11.11.1"),
    readCommandPath: async (command) => (command === "node" ? process.execPath : "/usr/bin/npm"),
    requiresSudo: async () => false,
    installFiles: async () => undefined,
    verifyInstalledVersion: async () => undefined,
    readInstalledVersion: async () => "hermes-fly 0.1.95",
    resolveInstallRef: async () => "v0.1.95",
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
  assert.equal(calls[0]?.installRef, "v0.1.95");
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
