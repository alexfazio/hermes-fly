import type { DeployRunnerPort } from "../ports/deploy-runner.port.js";
import type { DeployConfig } from "../ports/deploy-wizard.port.js";

export class ProvisionDeploymentUseCase {
  constructor(private readonly runner: DeployRunnerPort) {}

  async execute(
    config: DeployConfig,
    stderr: { write: (s: string) => void }
  ): Promise<{ ok: boolean; error?: string }> {
    // Step 1: Create app
    const appResult = await this.runner.createApp(config.appName, config.region);
    if (!appResult.ok) {
      const error = appResult.error ?? "failed to create app";
      if (error.includes("already") || error.includes("taken")) {
        stderr.write(`[error] App creation failed. Hint: the name '${config.appName}' may already be taken.\n`);
      } else {
        stderr.write(`[error] App creation failed. Details: ${error}\n`);
      }
      return { ok: false, error };
    }

    // Step 2: Create volume
    const volResult = await this.runner.createVolume(config.appName, config.region, config.volumeSize);
    if (!volResult.ok) {
      const error = volResult.error ?? "failed to create volume";
      stderr.write(`[error] Volume creation failed: ${error}\n`);
      return { ok: false, error };
    }

    // Step 3: Set secrets
    const secrets: Record<string, string> = {
      OPENROUTER_API_KEY: config.apiKey,
      HERMES_AGENT_REF: config.hermesRef,
      HERMES_DEPLOY_CHANNEL: config.channel
    };
    if (config.botToken) {
      secrets.TELEGRAM_BOT_TOKEN = config.botToken;
    }

    const secretsResult = await this.runner.setSecrets(config.appName, secrets);
    if (!secretsResult.ok) {
      const error = secretsResult.error ?? "failed to set secrets";
      stderr.write(`[error] Secrets setup failed: ${error}\n`);
      return { ok: false, error };
    }

    return { ok: true };
  }
}
