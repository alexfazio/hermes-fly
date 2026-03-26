import { describe, it } from "node:test";
import assert from "node:assert";
import { UpdateDeploymentUseCase } from "../../src/contexts/deploy/application/use-cases/update-deployment.js";
import type { UpdateRunnerPort } from "../../src/contexts/deploy/application/ports/update-runner.port.js";
import type { DeployWizardPort } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.js";

describe("UpdateDeploymentUseCase", () => {
  function makeRunner(overrides: Partial<UpdateRunnerPort> & { capturedBuildDir?: string } = {}): UpdateRunnerPort {
    return {
      checkAppExists: async () => ({ exists: true }),
      runUpdate: async (buildDir: string, appName: string) => {
        overrides.capturedBuildDir = buildDir;
        return { ok: true };
      },
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
      createBuildContext: async () => ({ buildDir: "/tmp/hermes-deploy-test-app-1234567890" }),
      fetchExistingConfig: async () => null,
      promptUpdateConfigChoice: async () => ({ keep: true }),
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
      checkAppExists: async () => ({ exists: false }),
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

  // REGRESSION TEST: Issue 1 - must use generated build directory
  it("uses the generated build directory during update (regression test)", async () => {
    const expectedBuildDir = "/tmp/hermes-deploy-test-app-9999999999";
    let capturedBuildDir: string | undefined;
    
    const runner = makeRunner({
      runUpdate: async (buildDir: string) => {
        capturedBuildDir = buildDir;
        return { ok: true };
      },
    });
    
    const wizard = makeWizard({
      createBuildContext: async () => ({ buildDir: expectedBuildDir }),
    });
    
    const useCase = new UpdateDeploymentUseCase(runner, wizard);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "edge" },
      stderr,
      stdout
    );

    assert.strictEqual(capturedBuildDir, expectedBuildDir, 
      "runUpdate must be called with the buildDir from createBuildContext, not empty string");
  });

  // REGRESSION TEST: Issue 2 - must honor HERMES_AGENT_REF override
  it("honors HERMES_AGENT_REF environment override (regression test)", async () => {
    const overrideRef = "abc123def456 emergency-patch";
    let capturedRef = "";
    
    const runner = makeRunner();
    const wizard = makeWizard({
      createBuildContext: async (config) => {
        capturedRef = config.hermesRef;
        return { buildDir: "/tmp/test" };
      },
    });
    
    const env = { HERMES_AGENT_REF: overrideRef };
    const useCase = new UpdateDeploymentUseCase(runner, wizard, env);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "stable" }, // stable channel, but override should win
      stderr,
      stdout
    );

    assert.strictEqual(capturedRef, overrideRef, 
      "HERMES_AGENT_REF environment variable must override channel default");
  });

  it("uses channel default when HERMES_AGENT_REF is empty", async () => {
    let capturedRef = "";
    
    const runner = makeRunner();
    const wizard = makeWizard({
      createBuildContext: async (config) => {
        capturedRef = config.hermesRef;
        return { buildDir: "/tmp/test" };
      },
    });
    
    const env = { HERMES_AGENT_REF: "" }; // empty override
    const useCase = new UpdateDeploymentUseCase(runner, wizard, env);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "edge" },
      stderr,
      stdout
    );

    assert.strictEqual(capturedRef, "main", 
      "Empty HERMES_AGENT_REF should fall back to channel default");
  });

  it("uses channel default when HERMES_AGENT_REF is whitespace only", async () => {
    let capturedRef = "";
    
    const runner = makeRunner();
    const wizard = makeWizard({
      createBuildContext: async (config) => {
        capturedRef = config.hermesRef;
        return { buildDir: "/tmp/test" };
      },
    });
    
    const env = { HERMES_AGENT_REF: "   \t\n  " }; // whitespace only
    const useCase = new UpdateDeploymentUseCase(runner, wizard, env);

    const stderr = { output: "", write(s: string) { this.output += s; } };
    const stdout = { output: "", write(s: string) { this.output += s; } };

    await useCase.execute(
      { appName: "test-app", channel: "edge" },
      stderr,
      stdout
    );

    assert.strictEqual(capturedRef, "main", 
      "Whitespace-only HERMES_AGENT_REF should fall back to channel default");
  });
});
