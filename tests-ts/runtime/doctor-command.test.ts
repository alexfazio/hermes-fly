import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { runDoctorCommand } from "../../src/commands/doctor.ts";
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

function makeIO() {
  const errLines: string[] = [];
  return {
    stderr: { write: (s: string) => { errLines.push(s); } },
    get errText() { return errLines.join(""); }
  };
}

describe("runDoctorCommand - all pass", () => {
  it("returns 0 when all 8 checks pass", async () => {
    const io = makeIO();
    const code = await runDoctorCommand(["-a", "test-app"], {
      checks: makeAllPassPort(),
      ...io
    });
    assert.equal(code, 0);
  });

  it("outputs 8 passed, 0 failed summary on success", async () => {
    const io = makeIO();
    await runDoctorCommand(["-a", "test-app"], {
      checks: makeAllPassPort(),
      ...io
    });
    assert.ok(io.errText.includes("8 passed"), `Expected '8 passed' in output: ${io.errText}`);
    assert.ok(io.errText.includes("0 failed"), `Expected '0 failed' in output: ${io.errText}`);
  });

  it("outputs [PASS] labels for each check", async () => {
    const io = makeIO();
    await runDoctorCommand(["-a", "test-app"], {
      checks: makeAllPassPort(),
      ...io
    });
    assert.ok(io.errText.includes("[PASS]"), `Expected [PASS] in output: ${io.errText}`);
  });
});

describe("runDoctorCommand - machine stopped", () => {
  it("returns 1 when machine is stopped", async () => {
    const io = makeIO();
    const code = await runDoctorCommand(["-a", "test-app"], {
      checks: makeAllPassPort({ checkMachineRunning: async () => false }),
      ...io
    });
    assert.equal(code, 1);
  });

  it("outputs FAIL and fly machine start hint", async () => {
    const io = makeIO();
    await runDoctorCommand(["-a", "test-app"], {
      checks: makeAllPassPort({ checkMachineRunning: async () => false }),
      ...io
    });
    assert.ok(io.errText.includes("[FAIL]"), `Expected [FAIL] in output: ${io.errText}`);
    assert.ok(io.errText.includes("fly machine start"), `Expected fly hint in output: ${io.errText}`);
  });
});

describe("runDoctorCommand - no app specified", () => {
  it("returns 1 when no app resolved", async () => {
    const io = makeIO();
    const code = await runDoctorCommand([], {
      checks: makeAllPassPort(),
      appName: null,
      ...io
    });
    assert.equal(code, 1);
    assert.ok(io.errText.includes("No app specified"), `Expected no-app error: ${io.errText}`);
  });
});

describe("runDoctorCommand - app not found", () => {
  it("returns 1 when app check fails", async () => {
    const io = makeIO();
    const code = await runDoctorCommand(["-a", "ghost-app"], {
      checks: makeAllPassPort({ checkAppExists: async () => false }),
      ...io
    });
    assert.equal(code, 1);
  });
});
