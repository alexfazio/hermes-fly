import type { DeployConfig, DeployWizardPort } from "../ports/deploy-wizard.port.js";
import type { PostDeployCleanupPort } from "../ports/post-deploy-cleanup.port.js";

const VALID_CHANNELS = new Set(["stable", "preview", "edge"]);

export type DeployWizardResult =
  | { kind: "ok" }
  | { kind: "failed"; error: string };

export type DeployChannel = "stable" | "preview" | "edge";

const VM_SIZE_LABELS = new Map<string, string>([
  ["shared-cpu-1x", "Starter (shared-cpu-1x, 256 MB)"],
  ["shared-cpu-2x", "Standard (shared-cpu-2x, 512 MB)"],
  ["performance-1x", "Pro (performance-1x, 2 GB)"],
  ["performance-2x", "Power (performance-2x, 4 GB)"],
]);

function resolveChannel(input: string): DeployChannel {
  return VALID_CHANNELS.has(input) ? (input as DeployChannel) : "stable";
}

function describeVmSize(vmSize: string): string {
  return VM_SIZE_LABELS.get(vmSize) ?? vmSize;
}

function describeTelegram(config: DeployConfig): string | undefined {
  if (!config.botToken) {
    return undefined;
  }
  if (config.telegramBotUsername && config.telegramBotName) {
    return `@${config.telegramBotUsername} (${config.telegramBotName})`;
  }
  if (config.telegramBotUsername) {
    return `@${config.telegramBotUsername}`;
  }
  if (config.telegramBotName) {
    return config.telegramBotName;
  }
  return "configured";
}

function describeTelegramAccess(config: DeployConfig): string | undefined {
  if (!config.botToken) {
    return undefined;
  }
  if (config.gatewayAllowAllUsers) {
    return "Anyone";
  }
  if (!config.telegramAllowedUsers) {
    return undefined;
  }

  const users = config.telegramAllowedUsers.split(",").map((value) => value.trim()).filter(Boolean);
  if (users.length === 1) {
    return `Only me (${users[0]})`;
  }
  if (users.length > 1) {
    return `Specific people (${users.join(", ")})`;
  }
  return undefined;
}

function buildTelegramChatLink(config: DeployConfig): string | undefined {
  if (!config.telegramBotUsername) {
    return undefined;
  }
  return `https://t.me/${config.telegramBotUsername}?start=${config.appName}`;
}

function describeAiAccess(provider: string): string {
  if (provider === "openai-codex") {
    return "ChatGPT subscription (OpenAI Codex)";
  }
  return "OpenRouter API key";
}

function writeCompletionSummary(stdout: { write: (s: string) => void }, config: DeployConfig): void {
  stdout.write("Deployment complete\n");
  stdout.write(`  Fly organization: ${config.orgSlug}\n`);
  stdout.write(`  Deployment name: ${config.appName}\n`);
  stdout.write(`  Location:        ${config.region}\n`);
  stdout.write(`  Server size:     ${describeVmSize(config.vmSize)}\n`);
  stdout.write(`  Storage:         ${config.volumeSize} GB\n`);
  stdout.write(`  AI access:       ${describeAiAccess(config.provider)}\n`);
  stdout.write(`  AI model:        ${config.model}\n`);
  if (config.reasoningEffort) {
    stdout.write(`  Reasoning:       ${config.reasoningEffort}\n`);
  }
  stdout.write(`  Hermes ref:      ${config.hermesRef.slice(0, 8)}\n`);
  stdout.write(`  Release channel: ${config.channel}\n`);

  const telegram = describeTelegram(config);
  if (telegram) {
    stdout.write(`  Telegram:        ${telegram}\n`);
    const access = describeTelegramAccess(config);
    if (access) {
      stdout.write(`  Telegram access: ${access}\n`);
    }
    if (config.telegramHomeChannel) {
      stdout.write(`  Home channel:    ${config.telegramHomeChannel}\n`);
    }
    const chatLink = buildTelegramChatLink(config);
    if (chatLink) {
      stdout.write(`  Chat link:       ${chatLink}\n`);
    }
  }

  stdout.write("\n");
  stdout.write("  Next steps:\n");
  stdout.write(`    - Check app status:  hermes-fly status -a ${config.appName}\n`);
  stdout.write(`    - View logs:         hermes-fly logs -a ${config.appName}\n`);
  stdout.write(`    - Run diagnostics:   hermes-fly doctor -a ${config.appName}\n`);
}

export class RunDeployWizardUseCase {
  constructor(
    private readonly port: DeployWizardPort,
    private readonly cleanupPort?: PostDeployCleanupPort
  ) {}

  async execute(
    opts: { autoInstall: boolean; channel: string },
    stderr: { write: (s: string) => void },
    stdout: { write: (s: string) => void } = { write: () => {} }
  ): Promise<DeployWizardResult> {
    const channel = resolveChannel(opts.channel);

    // Phase 1: Preflight checks
    const platformResult = await this.port.checkPlatform();
    if (!platformResult.ok) {
      stderr.write(`[error] Platform check failed: ${platformResult.error ?? "unsupported platform"}\n`);
      return { kind: "failed", error: platformResult.error ?? "unsupported platform" };
    }

    const prereqResult = await this.port.checkPrerequisites({ autoInstall: opts.autoInstall });
    if (!prereqResult.ok) {
      if (prereqResult.autoInstallDisabled) {
        stderr.write(`[error] '${prereqResult.missing ?? "fly"}' not found (auto-install disabled). Install manually and retry.\n`);
      } else if (prereqResult.error) {
        stderr.write(`[error] ${prereqResult.error}\n`);
      } else {
        stderr.write(`[error] Missing prerequisite: ${prereqResult.missing ?? "unknown"}\n`);
      }
      return { kind: "failed", error: `Missing prerequisite: ${prereqResult.missing}` };
    }

    const authResult = await this.port.checkAuth();
    if (!authResult.ok) {
      if (authResult.error && authResult.error !== "not authenticated") {
        stderr.write(`[error] ${authResult.error}\n`);
      } else {
        stderr.write(`[error] Not authenticated. Run: fly auth login\n`);
      }
      return { kind: "failed", error: authResult.error ?? "not authenticated" };
    }

    const connectResult = await this.port.checkConnectivity();
    if (!connectResult.ok) {
      stderr.write(`[error] No internet connectivity.\n`);
      return { kind: "failed", error: "no connectivity" };
    }

    // Phase 2: Collect config (interactive)
    let config: DeployConfig;
    try {
      config = await this.port.collectConfig({ channel });
    } catch (error) {
      const message = error instanceof Error ? error.message : "failed to collect deploy configuration";
      if (message === "Deployment cancelled.") {
        stderr.write(`${message}\n`);
      } else {
        stderr.write(`[error] ${message}\n`);
      }
      return { kind: "failed", error: message };
    }

    // Phase 3: Create build context
    const { buildDir } = await this.port.createBuildContext(config);

    // Phase 4: Provision resources
    const provisionResult = await this.port.provisionResources(config);
    if (!provisionResult.ok) {
      stderr.write(`[error] Provisioning failed: ${provisionResult.error ?? "unknown error"}\n`);
      return { kind: "failed", error: provisionResult.error ?? "provisioning failed" };
    }

    // Phase 5: Run deploy — preserve resources even on failure
    const deployResult = await this.port.runDeploy(buildDir, config);
    if (!deployResult.ok) {
      // Save app so resume works
      await this.port.saveApp(config.appName, config.region);
      stderr.write(`[error] Deploy failed: ${deployResult.error ?? "unknown error"}\n`);
      stderr.write(`Tip: run 'hermes-fly resume -a ${config.appName}' to retry post-deploy checks.\n`);
      return { kind: "failed", error: deployResult.error ?? "deploy failed" };
    }

    // Phase 6: Post-deploy check
    const postResult = await this.port.postDeployCheck(config.appName);
    if (!postResult.ok) {
      stderr.write(`[warn] Post-deploy check failed. App may still be starting up.\n`);
      stderr.write(`Tip: run 'hermes-fly resume -a ${config.appName}' to re-check.\n`);
    }

    // Save app configuration
    await this.port.saveApp(config.appName, config.region);

    writeCompletionSummary(stdout, config);

    const action = await this.port.chooseSuccessfulDeploymentAction(config);
    if (action === "destroy") {
      if (!this.cleanupPort) {
        stderr.write("[error] Destroy action requested, but no cleanup handler is available.\n");
        return { kind: "failed", error: "destroy handler unavailable" };
      }

      stdout.write("\nDestroying the deployment you just created...\n");
      const cleanupResult = await this.cleanupPort.destroyDeployment(config.appName, { stdout, stderr });
      if (!cleanupResult.ok) {
        if (cleanupResult.notFound) {
          return { kind: "failed", error: "destroyed app not found" };
        }
        stderr.write(`[error] Post-deploy cleanup failed: ${cleanupResult.error ?? "unknown error"}\n`);
        return { kind: "failed", error: cleanupResult.error ?? "post-deploy cleanup failed" };
      }

      if (config.botToken) {
        await this.port.showTelegramBotDeletionGuidance(config);
      }
    }

    return { kind: "ok" };
  }
}
