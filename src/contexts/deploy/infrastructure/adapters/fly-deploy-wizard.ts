import type { DeployConfig, DeployWizardPort } from "../../application/ports/deploy-wizard.port.js";
import { FlyDeployRunner } from "./fly-deploy-runner.js";
import { TemplateWriter } from "./template-writer.js";
import { NodeProcessRunner } from "../../../../adapters/process.js";
import { tmpdir } from "node:os";
import { join } from "node:path";

export class FlyDeployWizard implements DeployWizardPort {
  private readonly runner: FlyDeployRunner;
  private readonly templateWriter: TemplateWriter;
  private readonly process: NodeProcessRunner;
  private readonly env?: NodeJS.ProcessEnv;

  constructor(env?: NodeJS.ProcessEnv) {
    this.env = env;
    this.process = new NodeProcessRunner();
    this.runner = new FlyDeployRunner(this.process, env);
    this.templateWriter = new TemplateWriter();
  }

  async checkPlatform(): Promise<{ ok: boolean; error?: string }> {
    const platform = (this.env?.HERMES_FLY_PLATFORM ?? process.platform) as string;
    if (platform === "darwin" || platform === "linux") {
      return { ok: true };
    }
    return { ok: false, error: `Unsupported platform: ${platform}` };
  }

  async checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean }> {
    const env = this.env ?? process.env;
    const apiKey = (env.OPENROUTER_API_KEY ?? "").trim();
    if (!apiKey) {
      return { ok: false, missing: "OPENROUTER_API_KEY" };
    }
    const result = await this.process.run("which", ["fly"], { env: this.env });
    if (result.exitCode !== 0) {
      if (!opts.autoInstall) {
        return { ok: false, missing: "fly", autoInstallDisabled: true };
      }
      return { ok: false, missing: "fly" };
    }
    return { ok: true };
  }

  async checkAuth(): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.run("fly", ["auth", "whoami"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "not authenticated" };
    }
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
    const env = this.env ?? process.env;
    return {
      appName: env.HERMES_FLY_APP_NAME ?? "hermes-agent",
      region: env.HERMES_FLY_REGION ?? "iad",
      vmSize: env.HERMES_FLY_VM_SIZE ?? "shared-cpu-1x",
      volumeSize: Number(env.HERMES_FLY_VOLUME_SIZE ?? "1"),
      apiKey: env.OPENROUTER_API_KEY ?? "",
      model: env.HERMES_FLY_MODEL ?? "anthropic/claude-3-5-sonnet",
      channel: opts.channel,
      hermesRef: env.HERMES_FLY_VERSION ?? "latest",
      botToken: env.TELEGRAM_BOT_TOKEN ?? "",
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
      TELEGRAM_BOT_TOKEN: config.botToken,
    };
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
    const configDir = (this.env ?? process.env).HERMES_FLY_CONFIG_DIR
      ?? `${(this.env ?? process.env).HOME ?? process.env.HOME}/.hermes-fly`;
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
}
