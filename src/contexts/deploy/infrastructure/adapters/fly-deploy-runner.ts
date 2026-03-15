import type { DeployRunnerPort } from "../../application/ports/deploy-runner.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";

export class FlyDeployRunner implements DeployRunnerPort {
  constructor(
    private readonly runner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async createApp(appName: string, region: string): Promise<{ ok: boolean; error?: string }> {
    const result = await this.runner.run(
      "fly",
      ["apps", "create", appName, "--region", region, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) {
      return { ok: false, error: result.stderr || result.stdout };
    }
    return { ok: true };
  }

  async createVolume(appName: string, region: string, sizeGb: number): Promise<{ ok: boolean; error?: string }> {
    const result = await this.runner.run(
      "fly",
      ["volumes", "create", "hermes_data", "-a", appName, "--region", region, "--size", String(sizeGb), "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) {
      return { ok: false, error: result.stderr || result.stdout };
    }
    return { ok: true };
  }

  async setSecrets(appName: string, secrets: Record<string, string>): Promise<{ ok: boolean; error?: string }> {
    const pairs = Object.entries(secrets).map(([k, v]) => `${k}=${v}`);
    const result = await this.runner.run(
      "fly",
      ["secrets", "set", "--app", appName, ...pairs],
      { env: this.env }
    );
    if (result.exitCode !== 0) {
      return { ok: false, error: result.stderr || result.stdout };
    }
    return { ok: true };
  }
}
