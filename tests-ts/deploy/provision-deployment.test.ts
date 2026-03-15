import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ProvisionDeploymentUseCase } from "../../src/contexts/deploy/application/use-cases/provision-deployment.ts";
import type { DeployRunnerPort } from "../../src/contexts/deploy/application/ports/deploy-runner.port.ts";
import type { DeployConfig } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";

const DEFAULT_CONFIG: DeployConfig = {
  appName: "test-app",
  region: "iad",
  vmSize: "shared-cpu-1x",
  volumeSize: 5,
  apiKey: "sk-test",
  model: "anthropic/claude-sonnet-4-20250514",
  channel: "stable",
  hermesRef: "8eefbef91cd715cfe410bba8c13cfab4eb3040df",
  botToken: ""
};

function makeIO() {
  const lines: string[] = [];
  return {
    stderr: { write: (s: string) => { lines.push(s); } },
    get text() { return lines.join(""); }
  };
}

function makeRunner(overrides: Partial<DeployRunnerPort> = {}): DeployRunnerPort {
  return {
    createApp: async () => ({ ok: true }),
    createVolume: async () => ({ ok: true }),
    setSecrets: async () => ({ ok: true }),
    ...overrides
  };
}

describe("ProvisionDeploymentUseCase - happy path", () => {
  it("returns ok when all steps succeed", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner());
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, true);
  });
});

describe("ProvisionDeploymentUseCase - create app failure", () => {
  it("returns not ok when createApp fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createApp: async () => ({ ok: false, error: "Name has already been taken" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });

  it("outputs name-taken hint when app name is taken", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createApp: async () => ({ ok: false, error: "Name has already been taken" })
    }));
    await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.ok(
      io.text.includes("already") || io.text.includes("taken"),
      `expected taken hint, got: ${io.text}`
    );
  });
});

describe("ProvisionDeploymentUseCase - volume failure", () => {
  it("returns not ok when createVolume fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createVolume: async () => ({ ok: false, error: "volume quota exceeded" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });
});

describe("ProvisionDeploymentUseCase - secrets failure", () => {
  it("returns not ok when setSecrets fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async () => ({ ok: false, error: "secrets failed" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });
});
