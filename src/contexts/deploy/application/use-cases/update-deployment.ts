import type { UpdateRunnerPort } from "../ports/update-runner.port.js";
import type { DeployWizardPort, ExistingAppConfig } from "../ports/deploy-wizard.port.js";

const HERMES_AGENT_DEFAULT_REF = "8eefbef91cd715cfe410bba8c13cfab4eb3040df";
const HERMES_AGENT_EDGE_REF = "main";

export type UpdateResult =
  | { kind: "ok" }
  | { kind: "failed"; error: string };

export interface UpdateConfig {
  appName: string;
  channel: "stable" | "preview" | "edge";
}

export class UpdateDeploymentUseCase {
  constructor(
    private readonly runner: UpdateRunnerPort,
    private readonly wizard: DeployWizardPort,
    private readonly env: NodeJS.ProcessEnv = process.env
  ) {}

  async execute(
    config: UpdateConfig,
    stderr: { write: (s: string) => void },
    stdout: { write: (s: string) => void }
  ): Promise<UpdateResult> {
    // Phase 1: Pre-flight checks
    const platformResult = await this.wizard.checkPlatform();
    if (!platformResult.ok) {
      stderr.write(`[error] Platform check failed: ${platformResult.error ?? "unsupported platform"}\n`);
      return { kind: "failed", error: platformResult.error ?? "unsupported platform" };
    }

    const prereqResult = await this.wizard.checkPrerequisites({ autoInstall: true });
    if (!prereqResult.ok) {
      if (prereqResult.autoInstallDisabled) {
        stderr.write(`[error] '${prereqResult.missing ?? "fly"}' not found (auto-install disabled).\n`);
      } else if (prereqResult.error) {
        stderr.write(`[error] ${prereqResult.error}\n`);
      } else {
        stderr.write(`[error] Missing prerequisite: ${prereqResult.missing ?? "unknown"}\n`);
      }
      return { kind: "failed", error: `Missing prerequisite: ${prereqResult.missing}` };
    }

    const authResult = await this.wizard.checkAuth();
    if (!authResult.ok) {
      stderr.write(`[error] Not authenticated. Run: fly auth login\n`);
      return { kind: "failed", error: authResult.error ?? "not authenticated" };
    }

    // Phase 2: Verify app exists
    const exists = await this.runner.checkAppExists(config.appName);
    if (!exists) {
      stderr.write(`[error] App '${config.appName}' not found. Run 'hermes-fly deploy' to create it.\n`);
      return { kind: "failed", error: "app not found" };
    }

    // Phase 3: Fetch existing config and prompt for choice
    stdout.write(`Updating '${config.appName}' to ${config.channel} channel...\n`);
    const hermesRef = this.resolveHermesRef(config.channel);

    const existingConfig = await this.wizard.fetchExistingConfig(config.appName);
    let deployConfig: ExistingAppConfig;

    if (existingConfig) {
      const choice = await this.wizard.promptUpdateConfigChoice(existingConfig);
      if (choice.keep) {
        deployConfig = existingConfig;
      } else if (choice.config) {
        deployConfig = {
          region: choice.config.region,
          vmSize: choice.config.vmSize,
          volumeSize: choice.config.volumeSize,
        };
      } else {
        deployConfig = existingConfig;
      }
    } else {
      // Could not fetch config, use defaults
      stderr.write(`[warn] Could not fetch existing config, using defaults.\n`);
      deployConfig = {
        region: "iad",
        vmSize: "shared-cpu-2x",
        volumeSize: 1,
      };
    }

    // Phase 4: Generate update Dockerfile
    let buildDir: string;
    try {
      const result = await this.wizard.createBuildContext({
        orgSlug: "",
        appName: config.appName,
        region: deployConfig.region,
        vmSize: deployConfig.vmSize,
        volumeSize: deployConfig.volumeSize,
        provider: "",
        apiKey: "",
        model: "",
        hermesRef,
        botToken: "",
        channel: config.channel,
      });
      buildDir = result.buildDir;
    } catch (error) {
      const message = error instanceof Error ? error.message : "failed to create build context";
      stderr.write(`[error] ${message}\n`);
      return { kind: "failed", error: message };
    }

    // Phase 5: Run update (skip provisioning - app and volume already exist)
    stdout.write(`Building and deploying update...\n`);
    const updateResult = await this.runner.runUpdate(buildDir, config.appName);
    if (!updateResult.ok) {
      stderr.write(`[error] Update failed: ${updateResult.error ?? "unknown error"}\n`);
      return { kind: "failed", error: updateResult.error ?? "update failed" };
    }

    // Phase 6: Post-update check
    const checkResult = await this.wizard.postDeployCheck(config.appName);
    if (!checkResult.ok) {
      stderr.write(`[warn] Post-update check failed. App may still be starting up.\n`);
      stderr.write(`Tip: run 'hermes-fly status -a ${config.appName}' to check.\n`);
    }

    stdout.write(`\n✓ '${config.appName}' updated successfully to ${config.channel} channel.\n`);
    stdout.write(`  Channel: ${config.channel}\n`);
    stdout.write(`  Ref: ${hermesRef.slice(0, 8)}\n`);
    stdout.write(`\nNext steps:\n`);
    stdout.write(`  - Check status:  hermes-fly status -a ${config.appName}\n`);
    stdout.write(`  - View logs:     hermes-fly logs -a ${config.appName}\n`);
    stdout.write(`  - Run doctor:    hermes-fly doctor -a ${config.appName}\n`);

    return { kind: "ok" };
  }

  private resolveHermesRef(channel: "stable" | "preview" | "edge"): string {
    // Honor HERMES_AGENT_REF override for emergency rollback/pinned ref
    const override = (this.env.HERMES_AGENT_REF ?? "").trim();
    if (override.length > 0) {
      return override;
    }

    switch (channel) {
      case "edge":
        return HERMES_AGENT_EDGE_REF;
      case "preview":
        return HERMES_AGENT_DEFAULT_REF;
      default:
        return HERMES_AGENT_DEFAULT_REF;
    }
  }
}
