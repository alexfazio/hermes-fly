import { describe, it } from "node:test";
import assert from "node:assert";
import { UpdateDeploymentUseCase } from "../../src/contexts/deploy/application/use-cases/update-deployment.js";
import type { UpdateRunnerPort } from "../../src/contexts/deploy/application/ports/update-runner.port.js";
import type { DeployWizardPort } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.js";

describe("UpdateDeploymentUseCase", () => {
  function makeRunner(overrides: Partial<UpdateRunnerPort> = {}): UpdateRunnerPort {
    return {
      checkAppExists: async () => true,
      runUpdate: async () => ({ ok: true }),
      ...overrides,
    };
  }

  function makeWizard(overrides: Partial<DeployWizardPort> = {}): DeployWizardPort {
    return {
      checkPlatform: async () => ({ ok: true }),
      checkPrerequisites: async () => ({ ok: true }),
      checkAuth: async () => ({ ok: true }),
      checkConnectivity: async () => ({ ok: true }),
      collectConfig: async () => ({
        orgSlug: "test-org",
        appName: "test-app",
        region: "iad",
        vmSize: "shared-cpu-1x",
        volumeSize: 1,
        provider: "openrouter",
        apiKey: "test-key",
        model: "anthropic/claude-sonnet-4",
        hermesRef: "main",
        botToken: "",
        channel: "edge",
      }),
      createBuildContext: async () => ({ buildDir: "/tmp/test" }),
      provisionResources: async () => ({ ok: true }),
      runDeploy: async () => ({ ok: true }),
      postDeployCheck: async () => ({ ok: true }),
      saveApp: async () => {},
      finalizeMessagingSetup: async () => {},
      chooseSuccessfulDeploymentAction: async () => "conclude",
      showTelegramBotDeletionGuidance: async () => {},
      ...overrides,
    };
  }

  it("succeeds with valid app", async () => {
    const runner = makeRunner();
    const wizard = makeWizard();
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    const result = await useCase.execute(
      { appName: "test-app", channel: "edge" },
      stderr,
      stdout
    );

    assert.strictEqual(result.kind, "ok");
  });

  it("fails if app does not exist", async () => {
    const runner = makeRunner({
      checkAppExists: async () => false,
    });
    const wizard = makeWizard();
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    const result = await useCase.execute(
      { appName: "nonexistent-app", channel: "stable" },
      stderr,
      stdout
    );

    assert.strictEqual(result.kind, "failed");
    assert.ok(stderr.output.includes("not found"));
  });

  it("fails if not authenticated", async () => {
    const runner = makeRunner();
    const wizard = makeWizard({
      checkAuth: async () => ({ ok: false, error: "not authenticated" }),
    });
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    const result = await useCase.execute(
      { appName: "test-app", channel: "stable" },
      stderr,
      stdout
    );

    assert.strictEqual(result.kind, "failed");
    assert.ok(stderr.output.includes("Not authenticated"));
  });

  it("resolves correct ref for edge channel", async () => {
    let capturedRef = "";
    const runner = makeRunner();
    const wizard = makeWizard({
      createBuildContext: async (config) => {
        capturedRef = config.hermesRef;
        return { buildDir: "/tmp/test" };
      },
    });
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "edge" },
      stderr,
      stdout
    );

    assert.strictEqual(capturedRef, "main");
  });

  it("resolves correct ref for stable channel", async () => {
    let capturedRef = "";
    const runner = makeRunner();
    const wizard = makeWizard({
      createBuildContext: async (config) => {
        capturedRef = config.hermesRef;
        return { buildDir: "/tmp/test" };
      },
    });
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "stable" },
      stderr,
      stdout
    );

    assert.notStrictEqual(capturedRef, "main"); // Should be a pinned commit
    assert.ok(capturedRef.length > 8); // Should be a full commit hash
  });
});
