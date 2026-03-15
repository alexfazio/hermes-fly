import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { runDestroyCommand } from "../../src/commands/destroy.ts";
import type { DestroyRunnerPort } from "../../src/contexts/release/application/ports/destroy-runner.port.ts";

function makeRunner(overrides: Partial<DestroyRunnerPort> = {}): DestroyRunnerPort {
  return {
    destroyApp: async () => ({ ok: true }),
    cleanupVolumes: async () => {},
    telegramLogout: async () => {},
    removeConfig: async () => {},
    ...overrides
  };
}

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

describe("runDestroyCommand - --force flag", () => {
  it("--force with -a APP skips confirmation and returns 0 on success", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app", "--force"], { runner, ...io });
    assert.equal(code, 0);
  });

  it("--force with app name returns 0 on success", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["--force"], {
      runner,
      appName: "test-app",
      ...io
    });
    assert.equal(code, 0);
  });
});

describe("runDestroyCommand - confirmation flow", () => {
  it("confirmation 'yes' proceeds and returns 0", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "yes",
      ...io
    });
    assert.equal(code, 0);
  });

  it("confirmation 'no' aborts and returns 1", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "no",
      ...io
    });
    assert.equal(code, 1);
    const combined = io.outText + io.errText;
    assert.ok(combined.toLowerCase().includes("abort"), `Expected 'abort' in output: ${combined}`);
  });

  it("empty confirmation aborts and returns 1", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "",
      ...io
    });
    assert.equal(code, 1);
  });
});

describe("runDestroyCommand - not_found exit code", () => {
  it("returns 4 when app is not found", async () => {
    const runner = makeRunner({ destroyApp: async () => ({ ok: false }) });
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "ghost-app", "--force"], { runner, ...io });
    assert.equal(code, 4);
    assert.ok(io.errText.includes("not found"), `Expected 'not found' in stderr: ${io.errText}`);
  });
});

describe("runDestroyCommand - no app specified", () => {
  it("returns 1 with error message when no app and no config", async () => {
    const runner = makeRunner();
    const io = makeIO();
    // No appName, no -a, empty app list → error
    const code = await runDestroyCommand([], {
      runner,
      availableApps: [],
      ...io
    });
    assert.equal(code, 1);
  });
});
