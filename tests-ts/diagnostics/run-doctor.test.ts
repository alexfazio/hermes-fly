import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { RunDoctorUseCase } from "../../src/contexts/diagnostics/application/use-cases/run-doctor.ts";
import type { DoctorChecksPort } from "../../src/contexts/diagnostics/application/ports/doctor-checks.port.ts";

function makeAllPassPort(overrides: Partial<DoctorChecksPort> = {}): DoctorChecksPort {
  return {
    checkAppExists: async () => true,
    checkMachineRunning: async () => true,
    checkVolumesMounted: async () => true,
    checkSecretsSet: async () => true,
    checkHermesProcess: async () => true,
    checkGatewayHealth: async () => true,
    checkApiConnectivity: async () => true,
    checkDrift: async () => true,
    ...overrides
  };
}

describe("RunDoctorUseCase - all checks pass", () => {
  it("returns 8 passed, 0 failed when all checks pass", async () => {
    const useCase = new RunDoctorUseCase(makeAllPassPort());
    const result = await useCase.execute("test-app");
    assert.equal(result.passCount, 8);
    assert.equal(result.failCount, 0);
    assert.equal(result.allPassed, true);
  });

  it("returns 8 check results", async () => {
    const useCase = new RunDoctorUseCase(makeAllPassPort());
    const result = await useCase.execute("test-app");
    assert.equal(result.checks.length, 8);
  });

  it("all check results are pass=true", async () => {
    const useCase = new RunDoctorUseCase(makeAllPassPort());
    const result = await useCase.execute("test-app");
    for (const check of result.checks) {
      assert.equal(check.pass, true, `Expected ${check.key} to pass`);
    }
  });
});

describe("RunDoctorUseCase - app not found early exit", () => {
  it("returns early with only app check when app not found", async () => {
    const port = makeAllPassPort({ checkAppExists: async () => false });
    const useCase = new RunDoctorUseCase(port);
    const result = await useCase.execute("ghost-app");
    assert.equal(result.allPassed, false);
    assert.equal(result.failCount, 1);
    // Only the app check is run when app not found
    assert.ok(result.checks.length === 1, `Expected 1 check result, got ${result.checks.length}`);
  });

  it("app check key is 'app'", async () => {
    const port = makeAllPassPort({ checkAppExists: async () => false });
    const useCase = new RunDoctorUseCase(port);
    const result = await useCase.execute("ghost-app");
    assert.equal(result.checks[0].key, "app");
    assert.equal(result.checks[0].pass, false);
  });
});

describe("RunDoctorUseCase - mixed failures", () => {
  it("counts machine failure correctly", async () => {
    const port = makeAllPassPort({ checkMachineRunning: async () => false });
    const useCase = new RunDoctorUseCase(port);
    const result = await useCase.execute("test-app");
    assert.equal(result.failCount, 1);
    assert.equal(result.passCount, 7);
    assert.equal(result.allPassed, false);
  });

  it("check order: app, machine, volumes, secrets, hermes, gateway, api, drift", async () => {
    const useCase = new RunDoctorUseCase(makeAllPassPort());
    const result = await useCase.execute("test-app");
    const keys = result.checks.map((c) => c.key);
    assert.deepEqual(keys, [
      "app", "machine", "volumes", "secrets", "hermes", "gateway", "api", "drift"
    ]);
  });
});

describe("RunDoctorUseCase - drift check", () => {
  it("unverified drift counts as pass", async () => {
    const port = makeAllPassPort({ checkDrift: async () => "unverified" });
    const useCase = new RunDoctorUseCase(port);
    const result = await useCase.execute("test-app");
    assert.equal(result.passCount, 8);
    assert.equal(result.failCount, 0);
  });
});
