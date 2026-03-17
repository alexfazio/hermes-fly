import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ProvisionDeploymentUseCase } from "../../src/contexts/deploy/application/use-cases/provision-deployment.ts";
import type { DeployRunnerPort } from "../../src/contexts/deploy/application/ports/deploy-runner.port.ts";
import type { DeployConfig } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";

const DEFAULT_CONFIG: DeployConfig = {
  orgSlug: "personal",
  appName: "test-app",
  region: "iad",
  vmSize: "shared-cpu-1x",
  volumeSize: 5,
  provider: "openrouter",
  apiKey: "sk-test",
  model: "anthropic/claude-sonnet-4-20250514",
  channel: "stable",
  hermesRef: "8eefbef91cd715cfe410bba8c13cfab4eb3040df",
  botToken: ""
};

function makeIO() {
  const lines: string[] = [];
  return {
    stderr: { write: (s: string) => { lines.push(s); } },
    get text() { return lines.join(""); }
  };
}

function makeRunner(overrides: Partial<DeployRunnerPort> = {}): DeployRunnerPort {
  return {
    createApp: async () => ({ ok: true }),
    createVolume: async () => ({ ok: true }),
    setSecrets: async () => ({ ok: true }),
    ...overrides
  };
}

describe("ProvisionDeploymentUseCase - happy path", () => {
  it("returns ok when all steps succeed", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner());
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, true);
  });

  it("sets deploy secrets needed by the runtime", async () => {
    let capturedSecrets: Record<string, string> | null = null;
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async (_appName, secrets) => {
        capturedSecrets = secrets;
        return { ok: true };
      }
    }));

    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);

    assert.equal(result.ok, true);
    assert.deepEqual(capturedSecrets, {
      OPENROUTER_API_KEY: DEFAULT_CONFIG.apiKey,
      LLM_MODEL: DEFAULT_CONFIG.model,
      HERMES_LLM_PROVIDER: "openrouter",
      HERMES_APP_NAME: DEFAULT_CONFIG.appName,
      HERMES_AGENT_REF: DEFAULT_CONFIG.hermesRef,
      HERMES_DEPLOY_CHANNEL: DEFAULT_CONFIG.channel
    });
  });

  it("includes HERMES_REASONING_EFFORT when the deploy config selected one", async () => {
    let capturedSecrets: Record<string, string> | null = null;
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async (_appName, secrets) => {
        capturedSecrets = secrets;
        return { ok: true };
      }
    }));

    const result = await uc.execute({
      ...DEFAULT_CONFIG,
      model: "openai/gpt-5",
      reasoningEffort: "high"
    }, io.stderr);

    assert.equal(result.ok, true);
    assert.equal(capturedSecrets?.HERMES_REASONING_EFFORT, "high");
  });

  it("includes Telegram access-policy secrets when Telegram is configured in the wizard", async () => {
    let capturedSecrets: Record<string, string> | null = null;
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async (_appName, secrets) => {
        capturedSecrets = secrets;
        return { ok: true };
      }
    }));

    const result = await uc.execute({
      ...DEFAULT_CONFIG,
      botToken: "123:abc",
      telegramAllowedUsers: "12345,67890",
      telegramHomeChannel: "12345"
    }, io.stderr);

    assert.equal(result.ok, true);
    assert.equal(capturedSecrets?.TELEGRAM_BOT_TOKEN, "123:abc");
    assert.equal(capturedSecrets?.TELEGRAM_ALLOWED_USERS, "12345,67890");
    assert.equal(capturedSecrets?.TELEGRAM_HOME_CHANNEL, "12345");
    assert.equal(capturedSecrets?.GATEWAY_ALLOW_ALL_USERS, undefined);
  });

  it("sets Codex auth-store secrets when deploying with ChatGPT subscription access", async () => {
    let capturedSecrets: Record<string, string> | null = null;
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async (_appName, secrets) => {
        capturedSecrets = secrets;
        return { ok: true };
      }
    }));

    const result = await uc.execute({
      ...DEFAULT_CONFIG,
      provider: "openai-codex",
      apiKey: "",
      authJsonB64: "eyJ2ZXJzaW9uIjoxfQ==",
      model: "gpt-5.3-codex",
      reasoningEffort: "low",
      sttProvider: "local",
      sttModel: "base"
    }, io.stderr);

    assert.equal(result.ok, true);
    assert.deepEqual(capturedSecrets, {
      HERMES_AUTH_JSON_B64: "eyJ2ZXJzaW9uIjoxfQ==",
      LLM_MODEL: "gpt-5.3-codex",
      HERMES_LLM_PROVIDER: "openai-codex",
      HERMES_REASONING_EFFORT: "low",
      HERMES_STT_PROVIDER: "local",
      HERMES_STT_MODEL: "base",
      HERMES_APP_NAME: DEFAULT_CONFIG.appName,
      HERMES_AGENT_REF: DEFAULT_CONFIG.hermesRef,
      HERMES_DEPLOY_CHANNEL: DEFAULT_CONFIG.channel
    });
  });

  it("sets Hermes auth-store secrets when deploying with Nous Portal access", async () => {
    let capturedSecrets: Record<string, string> | null = null;
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async (_appName, secrets) => {
        capturedSecrets = secrets;
        return { ok: true };
      }
    }));

    const result = await uc.execute({
      ...DEFAULT_CONFIG,
      provider: "nous",
      apiKey: "",
      authJsonB64: "eyJ2ZXJzaW9uIjoxfQ==",
      model: "gpt-5.4",
      reasoningEffort: "medium"
    }, io.stderr);

    assert.equal(result.ok, true);
    assert.deepEqual(capturedSecrets, {
      HERMES_AUTH_JSON_B64: "eyJ2ZXJzaW9uIjoxfQ==",
      LLM_MODEL: "gpt-5.4",
      HERMES_LLM_PROVIDER: "nous",
      HERMES_REASONING_EFFORT: "medium",
      HERMES_APP_NAME: DEFAULT_CONFIG.appName,
      HERMES_AGENT_REF: DEFAULT_CONFIG.hermesRef,
      HERMES_DEPLOY_CHANNEL: DEFAULT_CONFIG.channel
    });
  });
});

describe("ProvisionDeploymentUseCase - create app failure", () => {
  it("returns not ok when createApp fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createApp: async () => ({ ok: false, error: "Name has already been taken" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });

  it("outputs name-taken hint when app name is taken", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createApp: async () => ({ ok: false, error: "Name has already been taken" })
    }));
    await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.ok(
      io.text.includes("already") || io.text.includes("taken"),
      `expected taken hint, got: ${io.text}`
    );
  });
});

describe("ProvisionDeploymentUseCase - volume failure", () => {
  it("returns not ok when createVolume fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      createVolume: async () => ({ ok: false, error: "volume quota exceeded" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });
});

describe("ProvisionDeploymentUseCase - secrets failure", () => {
  it("returns not ok when setSecrets fails", async () => {
    const io = makeIO();
    const uc = new ProvisionDeploymentUseCase(makeRunner({
      setSecrets: async () => ({ ok: false, error: "secrets failed" })
    }));
    const result = await uc.execute(DEFAULT_CONFIG, io.stderr);
    assert.equal(result.ok, false);
  });
});
