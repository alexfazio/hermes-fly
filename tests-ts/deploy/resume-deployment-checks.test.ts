import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ResumeDeploymentChecksUseCase } from "../../src/contexts/deploy/application/use-cases/resume-deployment-checks.ts";
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
    fetchStatus: async (_appName: string) => ({ ok: true, region: "iad" }),
    checkMachineRunning: async (_appName: string) => true,
    saveApp: async (_appName: string, _region: string) => {},
    ...overrides
  };
}

describe("ResumeDeploymentChecksUseCase - happy path", () => {
  it("returns ok on successful resume", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort());
    const result = await uc.execute("my-app", io.stderr);
    assert.equal(result.kind, "ok");
  });

  it("outputs Resuming deployment checks message", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort());
    await uc.execute("my-app", io.stderr);
    assert.ok(io.text.includes("Resuming deployment checks"), `expected resuming message, got: ${io.text}`);
  });

  it("outputs Resume complete message", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort());
    await uc.execute("my-app", io.stderr);
    assert.ok(io.text.includes("Resume complete"), `expected resume complete, got: ${io.text}`);
  });
});

describe("ResumeDeploymentChecksUseCase - fly status failure", () => {
  it("returns failed when fetchStatus fails", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort({
      fetchStatus: async () => ({ ok: false, region: null })
    }));
    const result = await uc.execute("my-app", io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("outputs error message when status fetch fails", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort({
      fetchStatus: async () => ({ ok: false, region: null })
    }));
    await uc.execute("my-app", io.stderr);
    assert.ok(io.text.includes("Could not fetch status"), `expected error, got: ${io.text}`);
  });
});

describe("ResumeDeploymentChecksUseCase - machine not running", () => {
  it("returns failed when machine not running", async () => {
    const io = makeIO();
    const uc = new ResumeDeploymentChecksUseCase(makePort({
      checkMachineRunning: async () => false
    }));
    const result = await uc.execute("my-app", io.stderr);
    assert.equal(result.kind, "failed");
  });
});
