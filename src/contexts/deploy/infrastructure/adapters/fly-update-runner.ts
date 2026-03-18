import type { UpdateRunnerPort } from "../../application/ports/update-runner.port.js";
import type { ForegroundProcessRunner } from "../../../../adapters/process.js";

export class FlyUpdateRunner implements UpdateRunnerPort {
  constructor(
    private readonly runner: ForegroundProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async checkAppExists(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "fly",
      ["apps", "list", "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0 || !result.stdout) {
      return false;
    }

    try {
      const apps = JSON.parse(result.stdout) as Array<{ Name?: string; name?: string }>;
      return apps.some(app => (app.Name ?? app.name) === appName);
    } catch {
      return false;
    }
  }

  async runUpdate(buildDir: string, appName: string): Promise<{ ok: boolean; error?: string }> {
    // For updates, we use fly deploy directly
    // The build context should already have the Dockerfile in place
    const result = await this.runner.runForeground(
      "fly",
      ["deploy", "--app", appName, "--wait-timeout", "5m0s"],
      { env: this.env, cwd: buildDir || undefined }
    );

    if (result.exitCode !== 0) {
      return { ok: false, error: "fly deploy failed" };
    }
    return { ok: true };
  }
}
