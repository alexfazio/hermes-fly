import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { runResumeCommand } from "../../src/commands/resume.ts";
import type { ResumeChecksPort } from "../../src/contexts/deploy/application/ports/resume-checks.port.ts";

function makeIO() {
  const lines: string[] = [];
  return {
    stderr: { write: (s: string) => { lines.push(s); } },
    get text() { return lines.join(""); }
  };
}

function makePort(overrides: Partial<ResumeChecksPort> = {}): ResumeChecksPort {
  return {
    fetchStatus: async () => ({ ok: true, region: "iad" }),
    checkMachineRunning: async () => true,
    saveApp: async () => {},
    ...overrides
  };
}

describe("runResumeCommand - all pass", () => {
  it("returns 0 on successful resume", async () => {
    const io = makeIO();
    const code = await runResumeCommand([], {
      appName: "my-app",
      checks: makePort(),
      stderr: io.stderr
    });
    assert.equal(code, 0);
  });

  it("outputs Resuming deployment checks", async () => {
    const io = makeIO();
    await runResumeCommand([], {
      appName: "my-app",
      checks: makePort(),
      stderr: io.stderr
    });
    assert.ok(io.text.includes("Resuming deployment checks"), `got: ${io.text}`);
  });

  it("outputs Resume complete on success", async () => {
    const io = makeIO();
    await runResumeCommand([], {
      appName: "my-app",
      checks: makePort(),
      stderr: io.stderr
    });
    assert.ok(io.text.includes("Resume complete"), `got: ${io.text}`);
  });
});

describe("runResumeCommand - no app specified", () => {
  it("returns 1 when no app resolved", async () => {
    const io = makeIO();
    const code = await runResumeCommand([], {
      appName: null,
      checks: makePort(),
      stderr: io.stderr
    });
    assert.equal(code, 1);
  });

  it("outputs No app specified error", async () => {
    const io = makeIO();
    await runResumeCommand([], {
      appName: null,
      checks: makePort(),
      stderr: io.stderr
    });
    assert.ok(io.text.includes("No app specified"), `got: ${io.text}`);
  });
});

describe("runResumeCommand - status fetch fails", () => {
  it("returns 1 when fetch status fails", async () => {
    const io = makeIO();
    const code = await runResumeCommand([], {
      appName: "my-app",
      checks: makePort({ fetchStatus: async () => ({ ok: false, region: null }) }),
      stderr: io.stderr
    });
    assert.equal(code, 1);
  });
});
