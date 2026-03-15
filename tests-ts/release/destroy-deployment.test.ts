import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { DestroyDeploymentUseCase } from "../../src/contexts/release/application/use-cases/destroy-deployment.ts";
import type { DestroyRunnerPort } from "../../src/contexts/release/application/ports/destroy-runner.port.ts";

function makeIO() {
  const outLines: string[] = [];
  const errLines: string[] = [];
  return {
    stdout: { write: (s: string) => { outLines.push(s); } },
    stderr: { write: (s: string) => { errLines.push(s); } },
    get outText() { return outLines.join(""); },
    get errText() { return errLines.join(""); }
  };
}

function makeRunner(overrides: Partial<DestroyRunnerPort> = {}): DestroyRunnerPort {
  return {
    destroyApp: async () => ({ ok: true }),
    cleanupVolumes: async () => {},
    telegramLogout: async () => {},
    removeConfig: async () => {},
    ...overrides
  };
}

describe("DestroyDeploymentUseCase - happy path", () => {
  it("returns ok on successful destroy", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    const result = await useCase.execute("test-app", io);
    assert.equal(result.kind, "ok");
  });

  it("calls cleanupVolumes before destroyApp", async () => {
    const callOrder: string[] = [];
    const runner = makeRunner({
      cleanupVolumes: async () => { callOrder.push("volumes"); },
      destroyApp: async () => { callOrder.push("destroy"); return { ok: true }; }
    });
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    await useCase.execute("test-app", io);
    assert.deepEqual(callOrder, ["volumes", "destroy"]);
  });

  it("calls telegramLogout (fail-open: continues even on error)", async () => {
    let telegramCalled = false;
    const runner = makeRunner({
      telegramLogout: async () => {
        telegramCalled = true;
        throw new Error("telegram failed");
      }
    });
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    const result = await useCase.execute("test-app", io);
    assert.equal(telegramCalled, true);
    assert.equal(result.kind, "ok");
  });

  it("calls removeConfig after successful destroyApp", async () => {
    let configRemoved = false;
    const runner = makeRunner({
      removeConfig: async () => { configRemoved = true; }
    });
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    await useCase.execute("test-app", io);
    assert.equal(configRemoved, true);
  });
});

describe("DestroyDeploymentUseCase - not_found path", () => {
  it("returns not_found when destroyApp returns ok:false", async () => {
    const runner = makeRunner({
      destroyApp: async () => ({ ok: false })
    });
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    const result = await useCase.execute("nonexistent-app", io);
    assert.equal(result.kind, "not_found");
  });

  it("writes 'not found' error to stderr on not_found", async () => {
    const runner = makeRunner({ destroyApp: async () => ({ ok: false }) });
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    await useCase.execute("ghost-app", io);
    assert.ok(io.errText.includes("not found"), `Expected 'not found' in stderr: ${io.errText}`);
  });
});

describe("DestroyDeploymentUseCase - ok output", () => {
  it("writes success message on ok", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const useCase = new DestroyDeploymentUseCase(runner);
    await useCase.execute("test-app", io);
    const combined = io.outText + io.errText;
    assert.ok(combined.includes("test-app"), `Expected app name in output: ${combined}`);
  });
});
