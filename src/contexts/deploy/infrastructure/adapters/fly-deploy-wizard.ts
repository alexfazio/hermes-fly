import type { DeployConfig, DeployWizardPort } from "../../application/ports/deploy-wizard.port.js";
import { FlyDeployRunner } from "./fly-deploy-runner.js";
import { TemplateWriter } from "./template-writer.js";
import { NodeProcessRunner, type ForegroundProcessRunner } from "../../../../adapters/process.js";
import { DeploymentIntent } from "../../domain/deployment-intent.js";
import { ReadlineDeployPrompts, type DeployPromptPort } from "./deploy-prompts.js";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { constants } from "node:fs";

const DEFAULT_APP_NAME_PREFIX = "hermes-agent";
const DEFAULT_REGION = "iad";
const DEFAULT_VM_SIZE = "shared-cpu-1x";
const DEFAULT_VOLUME_SIZE = 1;
const DEFAULT_MODEL = "anthropic/claude-3-5-sonnet";

export interface FlyDeployWizardDeps {
  process?: ForegroundProcessRunner;
  prompts?: DeployPromptPort;
  templateWriter?: TemplateWriter;
}

export class FlyDeployWizard implements DeployWizardPort {
  private readonly runner: FlyDeployRunner;
  private readonly templateWriter: TemplateWriter;
  private readonly process: ForegroundProcessRunner;
  private readonly prompts: DeployPromptPort;
  private readonly env: NodeJS.ProcessEnv;
  private readonly defaultAppName: string;

  constructor(env?: NodeJS.ProcessEnv, deps: FlyDeployWizardDeps = {}) {
    this.env = {
      ...process.env,
      ...(env ?? {})
    };
    this.process = deps.process ?? new NodeProcessRunner();
    this.runner = new FlyDeployRunner(this.process, this.env);
    this.templateWriter = deps.templateWriter ?? new TemplateWriter();
    this.prompts = deps.prompts ?? new ReadlineDeployPrompts();
    this.defaultAppName = this.buildDefaultAppName();
  }

  async checkPlatform(): Promise<{ ok: boolean; error?: string }> {
    const platform = (this.env?.HERMES_FLY_PLATFORM ?? process.platform) as string;
    if (platform === "darwin" || platform === "linux") {
      return { ok: true };
    }
    return { ok: false, error: `Unsupported platform: ${platform}` };
  }

  async checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean; error?: string }> {
    if (await this.ensureFlyAvailable()) {
      return { ok: true };
    }
    if (!opts.autoInstall) {
      return { ok: false, missing: "fly", autoInstallDisabled: true };
    }

    this.prompts.write("fly CLI not found. Attempting automatic installation...\n");
    const installResult = await this.installFlyCli();
    if (!installResult.ok) {
      return {
        ok: false,
        missing: "fly",
        error: installResult.error ?? "Failed to install fly CLI automatically. Install it from https://fly.io/docs/flyctl/install/ and retry."
      };
    }

    if (!(await this.ensureFlyAvailable())) {
      return {
        ok: false,
        missing: "fly",
        error: "fly CLI installation completed, but the binary is still not available on PATH. Restart your shell or install manually from https://fly.io/docs/flyctl/install/."
      };
    }

    this.prompts.write("fly CLI installed successfully.\n");
    return { ok: true };
  }

  async checkAuth(): Promise<{ ok: boolean; error?: string }> {
    let result = await this.process.run("fly", ["auth", "whoami"], { env: this.env });
    if (result.exitCode === 0) {
      return { ok: true };
    }

    if (!this.prompts.isInteractive()) {
      return { ok: false, error: "not authenticated" };
    }

    this.prompts.write("Not authenticated with Fly.io. Launching 'fly auth login' now...\n");
    const loginResult = await this.process.runForeground("fly", ["auth", "login"], { env: this.env });
    if (loginResult.exitCode !== 0) {
      return { ok: false, error: "Fly.io authentication did not complete successfully." };
    }

    result = await this.process.run("fly", ["auth", "whoami"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "Fly.io authentication completed, but no active Fly.io session is available." };
    }
    this.prompts.write("Fly.io authentication complete.\n");
    return { ok: true };
  }

  async checkConnectivity(): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.run("fly", ["version"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "fly CLI unreachable" };
    }
    return { ok: true };
  }

  async collectConfig(opts: { channel: "stable" | "preview" | "edge" }): Promise<DeployConfig> {
    const env = this.env;
    if (this.prompts.isInteractive()) {
      this.prompts.write("\nHermes Agent Deploy Configuration\n");
      this.prompts.write("Press Enter to accept the default shown in brackets.\n\n");
    }

    const appName = await this.collectTextValue("Deployment name", env.HERMES_FLY_APP_NAME, this.defaultAppName);
    const region = await this.collectTextValue("Region", env.HERMES_FLY_REGION, DEFAULT_REGION);
    const vmSize = await this.collectTextValue("VM size", env.HERMES_FLY_VM_SIZE, DEFAULT_VM_SIZE);
    const volumeSize = await this.collectVolumeSize(env.HERMES_FLY_VOLUME_SIZE);
    const apiKey = await this.collectRequiredSecret(
      "OPENROUTER_API_KEY",
      "OpenRouter API key",
      "https://openrouter.ai/settings/keys"
    );
    const model = await this.collectTextValue("Model", env.HERMES_FLY_MODEL, DEFAULT_MODEL);
    const botToken = await this.collectOptionalSecret("TELEGRAM_BOT_TOKEN", "Telegram bot token");
    const hermesRef = (env.HERMES_FLY_VERSION ?? "latest").trim() || "latest";

    const intent = DeploymentIntent.create({
      appName,
      region,
      vmSize,
      provider: "openrouter",
      model,
      channel: opts.channel
    });

    return {
      appName: intent.appName,
      region: intent.region,
      vmSize: intent.vmSize,
      volumeSize,
      apiKey,
      model: intent.model,
      channel: intent.channel,
      hermesRef,
      botToken,
    };
  }

  async createBuildContext(config: DeployConfig): Promise<{ buildDir: string }> {
    const buildDir = join(tmpdir(), `hermes-deploy-${config.appName}-${Date.now()}`);
    await this.templateWriter.createBuildContext(config, buildDir);
    return { buildDir };
  }

  async provisionResources(config: DeployConfig): Promise<{ ok: boolean; error?: string }> {
    const appResult = await this.runner.createApp(config.appName, config.region);
    if (!appResult.ok) return appResult;

    const volResult = await this.runner.createVolume(config.appName, config.region, config.volumeSize);
    if (!volResult.ok) return volResult;

    const secrets: Record<string, string> = {
      OPENROUTER_API_KEY: config.apiKey,
      LLM_MODEL: config.model,
      HERMES_AGENT_REF: config.hermesRef,
      HERMES_DEPLOY_CHANNEL: config.channel,
      HERMES_LLM_PROVIDER: "openrouter",
      HERMES_APP_NAME: config.appName,
    };
    if (config.botToken) {
      secrets.TELEGRAM_BOT_TOKEN = config.botToken;
    }
    return this.runner.setSecrets(config.appName, secrets);
  }

  async runDeploy(buildDir: string, config: DeployConfig): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.run(
      "fly",
      ["deploy", "--app", config.appName, "--config", `${buildDir}/fly.toml`, "--dockerfile", `${buildDir}/Dockerfile`],
      { env: this.env }
    );
    if (result.exitCode !== 0) {
      return { ok: false, error: result.stderr || result.stdout };
    }
    return { ok: true };
  }

  async postDeployCheck(appName: string): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.run("fly", ["status", "--app", appName, "--json"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "status check failed" };
    }
    return { ok: true };
  }

  async saveApp(appName: string, region: string): Promise<void> {
    const { readFile, writeFile, mkdir } = await import("node:fs/promises");
    const { join: pathJoin } = await import("node:path");
    const configDir = this.env.HERMES_FLY_CONFIG_DIR
      ?? `${this.env.HOME ?? process.env.HOME}/.hermes-fly`;
    await mkdir(configDir, { recursive: true });
    const configPath = pathJoin(configDir, "config.yaml");

    let existing = "";
    try { existing = await readFile(configPath, "utf8"); } catch { /* file may not exist */ }

    const allLines = existing.split(/\r?\n/).filter(l => l.trim() !== "");
    const withoutCurrentApp = allLines.filter(l => !/^current_app:/.test(l));

    // Split at apps: header
    const appsIdx = withoutCurrentApp.findIndex(l => /^apps:$/.test(l.trimEnd()));
    const preLines = appsIdx === -1 ? withoutCurrentApp : withoutCurrentApp.slice(0, appsIdx);
    const appsBodyRaw = appsIdx === -1 ? [] : withoutCurrentApp.slice(appsIdx + 1);

    // Split trailing top-level lines (lines not starting with two spaces)
    const trailingStartIdx = appsBodyRaw.findIndex(l => !/^  /.test(l));
    const appsSectionLines = trailingStartIdx === -1 ? appsBodyRaw : appsBodyRaw.slice(0, trailingStartIdx);
    const trailingTopLevelLines = trailingStartIdx === -1 ? [] : appsBodyRaw.slice(trailingStartIdx);

    // Parse existing entries with normalized names
    const entries: { name: string; lines: string[] }[] = [];
    let current: { name: string; lines: string[] } | null = null;
    for (const line of appsSectionLines) {
      const m = line.match(/^  - name:[ \t]*(.+)$/);
      if (m) {
        if (current !== null) entries.push(current);
        current = { name: m[1].trim(), lines: [line] };
      } else if (current !== null) {
        current.lines.push(line);
      }
    }
    if (current !== null) entries.push(current);

    // Dedup by normalized name, then append updated entry
    const filtered = entries.filter(e => e.name !== appName);
    filtered.push({ name: appName, lines: [`  - name: ${appName}`, `    region: ${region}`] });

    const newLines = [
      `current_app: ${appName}`,
      ...preLines,
      "apps:",
      ...filtered.flatMap(e => e.lines),
      ...trailingTopLevelLines,
    ];
    await writeFile(configPath, newLines.join("\n") + "\n", "utf8");
  }

  private async collectTextValue(label: string, envValue: string | undefined, fallback: string): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return fallback;
    }

    while (true) {
      const answer = await this.prompts.ask(`${label} [${fallback}]: `);
      const value = answer.length > 0 ? answer : fallback;
      if (value.trim().length > 0) {
        return value.trim();
      }
      this.prompts.write(`${label} cannot be empty.\n`);
    }
  }

  private async collectVolumeSize(envValue: string | undefined): Promise<number> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return this.parseVolumeSize(preset, "HERMES_FLY_VOLUME_SIZE");
    }
    if (!this.prompts.isInteractive()) {
      return DEFAULT_VOLUME_SIZE;
    }

    while (true) {
      const answer = await this.prompts.ask(`Volume size in GB [${DEFAULT_VOLUME_SIZE}]: `);
      const value = answer.length > 0 ? answer : String(DEFAULT_VOLUME_SIZE);
      try {
        return this.parseVolumeSize(value, "volume size");
      } catch (error) {
        this.prompts.write(`${error instanceof Error ? error.message : "Volume size must be a positive integer."}\n`);
      }
    }
  }

  private async collectRequiredSecret(envKey: string, label: string, helpUrl: string): Promise<string> {
    const env = this.env;
    const preset = (env[envKey] ?? "").trim();
    if (preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      throw new Error(`${envKey} is required in non-interactive mode. Run from a terminal to use the wizard or export ${envKey} first.`);
    }

    this.prompts.write(`Get your ${label.toLowerCase()} at: ${helpUrl}\n`);
    while (true) {
      const answer = await this.prompts.ask(`${label} (required): `);
      if (answer.trim().length > 0) {
        return answer.trim();
      }
      this.prompts.write(`${envKey} cannot be empty.\n`);
    }
  }

  private async collectOptionalSecret(envKey: string, label: string): Promise<string> {
    const env = this.env;
    const preset = (env[envKey] ?? "").trim();
    if (preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return "";
    }
    return (await this.prompts.ask(`${label} (optional, press Enter to skip): `)).trim();
  }

  private parseVolumeSize(value: string, label: string): number {
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`${label} must be a positive integer.`);
    }
    return parsed;
  }

  private async ensureFlyAvailable(): Promise<boolean> {
    const flyPath = await this.findExecutableOnPath("fly");
    if (flyPath && await this.canRunFlyBinary(flyPath)) {
      return true;
    }

    const home = this.env.HOME ?? process.env.HOME;
    if (home) {
      const flyPath = join(home, ".fly", "bin", "fly");
      if (await this.isExecutable(flyPath)) {
        this.prependPath(dirname(flyPath));
        if (await this.canRunFlyBinary(flyPath)) {
          return true;
        }
      }
    }

    return false;
  }

  private async canRunFlyBinary(command: string): Promise<boolean> {
    const versionResult = await this.process.run(command, ["version"], { env: this.env });
    return versionResult.exitCode === 0;
  }

  private prependPath(dir: string): void {
    const current = this.env.PATH ?? process.env.PATH ?? "";
    const parts = current.split(":").filter(Boolean);
    if (!parts.includes(dir)) {
      this.env.PATH = `${dir}${current.length > 0 ? `:${current}` : ""}`;
    }
  }

  private async installFlyCli(): Promise<{ ok: boolean; error?: string }> {
    const platform = this.env.HERMES_FLY_PLATFORM ?? process.platform;
    const override = (this.env.HERMES_FLY_FLYCTL_INSTALL_CMD ?? "").trim();
    const command =
      override.length > 0
        ? override
        : platform === "darwin"
          ? await this.resolveMacFlyInstallCommand()
          : platform === "linux"
            ? "curl -L https://fly.io/install.sh | sh"
            : "";

    if (command.length === 0) {
      return {
        ok: false,
        error: `Automatic fly installation is unsupported on ${platform}. Install fly manually from https://fly.io/docs/flyctl/install/.`
      };
    }

    const shellResult = await this.process.run("bash", ["-lc", command], { env: this.env });
    if (shellResult.exitCode !== 0) {
      const details = shellResult.stderr.trim() || shellResult.stdout.trim();
      return {
        ok: false,
        error: details.length > 0
          ? `Failed to install fly CLI automatically: ${details}`
          : "Failed to install fly CLI automatically. Install it from https://fly.io/docs/flyctl/install/ and retry."
      };
    }

    const home = this.env.HOME ?? process.env.HOME;
    if (home) {
      this.prependPath(join(home, ".fly", "bin"));
    }
    return { ok: true };
  }

  private async resolveMacFlyInstallCommand(): Promise<string> {
    if (await this.findExecutableOnPath("brew")) {
      return "brew install flyctl";
    }
    return "curl -L https://fly.io/install.sh | sh";
  }

  private async findExecutableOnPath(command: string): Promise<string | null> {
    const pathValue = this.env.PATH ?? process.env.PATH ?? "";
    for (const dir of pathValue.split(":")) {
      if (!dir) {
        continue;
      }
      const candidate = join(dir, command);
      if (await this.isExecutable(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  private async isExecutable(path: string): Promise<boolean> {
    const { access } = await import("node:fs/promises");
    try {
      await access(path, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }

  private buildDefaultAppName(): string {
    const explicit = (this.env.HERMES_FLY_DEFAULT_APP_NAME ?? "").trim();
    if (explicit.length > 0) {
      return explicit;
    }

    const uid =
      (this.env.UID ?? "").trim() || (
        typeof process.getuid === "function"
          ? String(process.getuid())
          : ""
      );
    const suffix = randomBytes(2).toString("hex");
    return [DEFAULT_APP_NAME_PREFIX, uid, suffix].filter((part) => part.length > 0).join("-");
  }
}
