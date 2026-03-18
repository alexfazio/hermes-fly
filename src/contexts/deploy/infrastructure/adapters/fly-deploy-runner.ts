import type { DeployRunnerPort } from "../../application/ports/deploy-runner.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";

export class FlyDeployRunner implements DeployRunnerPort {
  constructor(
    private readonly runner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async createApp(appName: string, orgSlug: string): Promise<{ ok: boolean; error?: string }> {
    const result = await this.runner.run(
      "fly",
      ["apps", "create", appName, "--org", orgSlug, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) {
      const error = result.stderr || result.stdout;
      if (/name has already been taken/i.test(error)) {
        return {
          ok: false,
          error: `Deployment name '${appName}' is already taken on Fly.io. Choose another name and retry.`
        };
      }
      return { ok: false, error };
    }
    return { ok: true };
  }

  async createVolume(appName: string, region: string, sizeGb: number): Promise<{ ok: boolean; error?: string }> {
    const primaryArgs = [
      "volumes", "create", "hermes_data", "-a", appName, "--region", region, "--size", String(sizeGb), "--json", "--yes"
    ];
    let result = await this.runner.run("fly", primaryArgs, { env: this.env });
    if (result.exitCode !== 0 && this.isUnknownLongRegionFlag(result.stderr || result.stdout)) {
      result = await this.runner.run(
        "fly",
        ["volumes", "create", "hermes_data", "-a", appName, "-r", region, "--size", String(sizeGb), "--json", "--yes"],
        { env: this.env }
      );
    }
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

  private isUnknownLongRegionFlag(output: string): boolean {
    return output.includes("unknown flag: --region");
  }
}
