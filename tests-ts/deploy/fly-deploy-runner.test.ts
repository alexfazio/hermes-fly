import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { ProcessResult, ProcessRunner } from "../../src/adapters/process.ts";
import { FlyDeployRunner } from "../../src/contexts/deploy/infrastructure/adapters/fly-deploy-runner.ts";

class StubProcessRunner implements ProcessRunner {
  readonly calls: Array<{ command: string; args: string[]; env?: NodeJS.ProcessEnv }> = [];

  constructor(private readonly results: ProcessResult[]) {}

  async run(command: string, args: string[], options: { env?: NodeJS.ProcessEnv } = {}): Promise<ProcessResult> {
    this.calls.push({ command, args, env: options.env });
    const next = this.results.shift();
    if (!next) {
      throw new Error("no queued process result");
    }
    return next;
  }

  async runStreaming(): Promise<{ exitCode: number }> {
    throw new Error("runStreaming should not be called in FlyDeployRunner tests");
  }
}

describe("FlyDeployRunner", () => {
  it("creates apps without passing the unsupported --region flag", async () => {
    const runner = new StubProcessRunner([{ exitCode: 0, stdout: "{\"name\":\"test-app\"}", stderr: "" }]);
    const deployRunner = new FlyDeployRunner(runner, { TEST_ENV: "1" });

    const result = await deployRunner.createApp("test-app", "personal");

    assert.equal(result.ok, true);
    assert.equal(runner.calls.length, 1);
    assert.deepEqual(runner.calls[0]?.args, ["apps", "create", "test-app", "--org", "personal", "--json"]);
    assert.equal(runner.calls[0]?.env?.TEST_ENV, "1");
  });

  it("returns a friendly name-taken error when Fly rejects an app name", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 1, stdout: "", stderr: "Validation failed: Name has already been taken" }
    ]);
    const deployRunner = new FlyDeployRunner(runner);

    const result = await deployRunner.createApp("taken-app", "personal");

    assert.deepEqual(result, {
      ok: false,
      error: "Deployment name 'taken-app' is already taken on Fly.io. Choose another name and retry."
    });
  });

  it("retries volume creation with -r when fly rejects --region", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 1, stdout: "", stderr: "Error: unknown flag: --region" },
      { exitCode: 0, stdout: "{\"id\":\"vol_test123\"}", stderr: "" }
    ]);
    const deployRunner = new FlyDeployRunner(runner);

    const result = await deployRunner.createVolume("test-app", "fra", 5);

    assert.equal(result.ok, true);
    assert.equal(runner.calls.length, 2);
    assert.deepEqual(runner.calls[0]?.args, [
      "volumes", "create", "hermes_data", "-a", "test-app", "--region", "fra", "--size", "5", "--json", "--yes"
    ]);
    assert.deepEqual(runner.calls[1]?.args, [
      "volumes", "create", "hermes_data", "-a", "test-app", "-r", "fra", "--size", "5", "--json", "--yes"
    ]);
  });

  it("returns the original volume error when the failure is unrelated to --region", async () => {
    const runner = new StubProcessRunner([
      { exitCode: 1, stdout: "", stderr: "Error: volume quota exceeded" }
    ]);
    const deployRunner = new FlyDeployRunner(runner);

    const result = await deployRunner.createVolume("test-app", "fra", 5);

    assert.deepEqual(result, { ok: false, error: "Error: volume quota exceeded" });
    assert.equal(runner.calls.length, 1);
  });
});
