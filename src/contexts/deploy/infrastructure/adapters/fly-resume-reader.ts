import type { ResumeChecksPort } from "../../application/ports/resume-checks.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";

export class FlyResumeReader implements ResumeChecksPort {
  constructor(
    private readonly runner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async fetchStatus(appName: string): Promise<{ ok: boolean; region: string | null }> {
    const result = await this.runner.run(
      "fly",
      ["status", "--app", appName, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) return { ok: false, region: null };
    try {
      const data = JSON.parse(result.stdout);
      const region = data.Region ?? data.region ?? null;
      return { ok: true, region };
    } catch {
      return { ok: true, region: null };
    }
  }

  async checkMachineRunning(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "fly",
      ["status", "--app", appName, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) return false;
    try {
      const data = JSON.parse(result.stdout);
      const machines = data.Machines ?? data.machines ?? [];
      return machines.some((m: { state?: string }) => m.state === "started");
    } catch {
      return false;
    }
  }

  async saveApp(appName: string, region: string): Promise<void> {
    const configDir = this.env?.HERMES_FLY_CONFIG_DIR ?? "";
    if (!configDir) return;

    const { writeFile, mkdir, readFile } = await import("node:fs/promises");
    const { join } = await import("node:path");

    await mkdir(configDir, { recursive: true });
    const configPath = join(configDir, "config.yaml");

    let existing = "";
    try {
      existing = await readFile(configPath, "utf8");
    } catch {
      // File may not exist yet
    }

    const appEntry = `  - name: ${appName}\n    region: ${region}\n`;
    if (!existing.includes(`name: ${appName}`)) {
      const updated = existing.trimEnd() + (existing ? "\n" : "apps:\n") + appEntry;
      await writeFile(configPath, updated, "utf8");
    }
  }
}
