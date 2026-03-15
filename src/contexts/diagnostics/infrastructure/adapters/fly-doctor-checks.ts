import type { DoctorChecksPort } from "../../application/ports/doctor-checks.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";

export class FlyDoctorChecks implements DoctorChecksPort {
  constructor(
    private readonly runner: ProcessRunner,
    private readonly appName: string,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async checkAppExists(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "fly",
      ["status", "--app", appName, "--json"],
      { env: this.env }
    );
    return result.exitCode === 0;
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

  async checkVolumesMounted(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "fly",
      ["volumes", "list", "-a", appName, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) return false;
    try {
      const volumes = JSON.parse(result.stdout);
      return Array.isArray(volumes) && volumes.length > 0;
    } catch {
      return false;
    }
  }

  async checkSecretsSet(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "fly",
      ["secrets", "list", "--app", appName, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) return false;
    try {
      const secrets = JSON.parse(result.stdout);
      return Array.isArray(secrets) && secrets.length > 0;
    } catch {
      return false;
    }
  }

  async checkHermesProcess(_appName: string): Promise<boolean> {
    // Simplified: if machine is running, assume hermes process is running
    return this.checkMachineRunning(_appName);
  }

  async checkGatewayHealth(appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "curl",
      ["-sf", "--max-time", "5", `https://${appName}.fly.dev/health`],
      { env: this.env }
    );
    return result.exitCode === 0;
  }

  async checkApiConnectivity(_appName: string): Promise<boolean> {
    const result = await this.runner.run(
      "curl",
      ["-sf", "--max-time", "5", "https://openrouter.ai"],
      { env: this.env }
    );
    return result.exitCode === 0;
  }

  async checkDrift(appName: string): Promise<boolean | "unverified"> {
    // Read local deploy provenance
    const configDir = this.env?.HERMES_FLY_CONFIG_DIR ?? "";
    if (!configDir) return "unverified";

    const { readFile } = await import("node:fs/promises");
    const { join } = await import("node:path");

    let localYaml: string;
    try {
      localYaml = await readFile(join(configDir, "deploys", `${appName}.yaml`), "utf8");
    } catch {
      return "unverified";
    }

    // Extract channel and ref from local config
    const channelMatch = localYaml.match(/deploy_channel:\s*(\S+)/);
    const refMatch = localYaml.match(/hermes_agent_ref:\s*(\S+)/);
    if (!channelMatch || !refMatch) return "unverified";

    // Fetch runtime manifest
    const manifestResult = await this.runner.run(
      "fly",
      ["ssh", "console", "-a", appName, "-C", "cat /app/.hermes-manifest.json"],
      { env: this.env }
    );
    if (manifestResult.exitCode !== 0) return "unverified";

    try {
      const manifest = JSON.parse(manifestResult.stdout);
      return (
        manifest.deploy_channel === channelMatch[1] &&
        manifest.hermes_agent_ref === refMatch[1]
      );
    } catch {
      return "unverified";
    }
  }
}
