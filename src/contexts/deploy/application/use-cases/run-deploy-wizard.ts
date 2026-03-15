import type { DeployWizardPort } from "../ports/deploy-wizard.port.js";

const VALID_CHANNELS = new Set(["stable", "preview", "edge"]);

export type DeployWizardResult =
  | { kind: "ok" }
  | { kind: "failed"; error: string };

export type DeployChannel = "stable" | "preview" | "edge";

function resolveChannel(input: string): DeployChannel {
  return VALID_CHANNELS.has(input) ? (input as DeployChannel) : "stable";
}

export class RunDeployWizardUseCase {
  constructor(private readonly port: DeployWizardPort) {}

  async execute(
    opts: { autoInstall: boolean; channel: string },
    stderr: { write: (s: string) => void }
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
      } else {
        stderr.write(`[error] Missing prerequisite: ${prereqResult.missing ?? "unknown"}\n`);
      }
      return { kind: "failed", error: `Missing prerequisite: ${prereqResult.missing}` };
    }

    const authResult = await this.port.checkAuth();
    if (!authResult.ok) {
      stderr.write(`[error] Not authenticated. Run: fly auth login\n`);
      return { kind: "failed", error: authResult.error ?? "not authenticated" };
    }

    const connectResult = await this.port.checkConnectivity();
    if (!connectResult.ok) {
      stderr.write(`[error] No internet connectivity.\n`);
      return { kind: "failed", error: "no connectivity" };
    }

    // Phase 2: Collect config (interactive)
    const config = await this.port.collectConfig({ channel });

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

    return { kind: "ok" };
  }
}
