import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { ProcessResult, ProcessRunner } from "../../src/adapters/process.ts";
import { FlyDoctorChecks } from "../../src/contexts/diagnostics/infrastructure/adapters/fly-doctor-checks.ts";

class StubProcessRunner implements ProcessRunner {
  readonly calls: Array<{ command: string; args: string[] }> = [];

  constructor(private readonly results: ProcessResult[]) {}

  async run(command: string, args: string[]): Promise<ProcessResult> {
    this.calls.push({ command, args });
    const next = this.results.shift();
    if (!next) {
      throw new Error("no queued process result");
    }
    return next;
  }

  async runStreaming(): Promise<{ exitCode: number }> {
    throw new Error("runStreaming should not be called in FlyDoctorChecks tests");
  }
}

describe("FlyDoctorChecks.checkMachineRunning", () => {
  it("uses fly machine list and returns true when a machine is started", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 0, stdout: JSON.stringify([{ id: "machine123", state: "started" }]), stderr: "" }
    ]);
    const checks = new FlyDoctorChecks(runner, "test-app");

    const result = await checks.checkMachineRunning("test-app");

    assert.equal(result, true);
    assert.deepEqual(runner.calls[0]?.args, ["machine", "list", "-a", "test-app", "--json"]);
  });
});

describe("FlyDoctorChecks.checkGatewayHealth", () => {
  it("uses Telegram getMe over fly ssh when TELEGRAM_BOT_TOKEN is configured", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 0, stdout: JSON.stringify([{ Name: "TELEGRAM_BOT_TOKEN", Digest: "abc123" }]), stderr: "" },
      { exitCode: 0, stdout: "", stderr: "" }
    ]);
    const checks = new FlyDoctorChecks(runner, "test-app");

    const result = await checks.checkGatewayHealth("test-app");

    assert.equal(result, true);
    assert.deepEqual(runner.calls[0]?.args, ["secrets", "list", "--app", "test-app", "--json"]);
    assert.deepEqual(runner.calls[1]?.args, [
      "ssh", "console", "--app", "test-app", "-C",
      "sh -lc 'curl -sf --max-time 10 \"https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe\" >/dev/null 2>&1'"
    ]);
  });

  it("uses hermes gateway status over fly ssh when WhatsApp is configured", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 0, stdout: JSON.stringify([{ Name: "HERMES_FLY_WHATSAPP_PENDING", Digest: "abc123" }]), stderr: "" },
      { exitCode: 0, stdout: "Hermes gateway is running\n", stderr: "" }
    ]);
    const checks = new FlyDoctorChecks(runner, "test-app");

    const result = await checks.checkGatewayHealth("test-app");

    assert.equal(result, true);
    assert.deepEqual(runner.calls[1]?.args, [
      "ssh", "console", "--app", "test-app", "-C",
      "sh -lc 'cd /root/.hermes && HERMES_DIR=/root/.hermes HOME=/root/.hermes /opt/hermes/hermes-agent/venv/bin/hermes gateway status'"
    ]);
  });

  it("falls back to machine state when no messaging secrets are configured", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 0, stdout: "[]", stderr: "" },
      { exitCode: 0, stdout: JSON.stringify([{ id: "machine123", state: "started" }]), stderr: "" }
    ]);
    const checks = new FlyDoctorChecks(runner, "test-app");

    const result = await checks.checkGatewayHealth("test-app");

    assert.equal(result, true);
    assert.deepEqual(runner.calls[1]?.args, ["machine", "list", "-a", "test-app", "--json"]);
  });
});
