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
      ["machine", "list", "-a", appName, "--json"],
      { env: this.env }
    );
    if (result.exitCode !== 0) return false;
    return this.machineStates(result.stdout).includes("started");
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
    const secretsResult = await this.runner.run(
      "fly",
      ["secrets", "list", "--app", appName, "--json"],
      { env: this.env }
    );
    if (secretsResult.exitCode === 0 && this.hasSecret(secretsResult.stdout, "TELEGRAM_BOT_TOKEN")) {
      const sshResult = await this.runner.run(
        "fly",
        [
          "ssh", "console", "--app", appName, "-C",
          this.telegramGetMeProbeCommand()
        ],
        { env: this.env }
      );
      return sshResult.exitCode === 0;
    }

    return this.checkMachineRunning(appName);
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

  private machineStates(stdout: string): string[] {
    try {
      const parsed = JSON.parse(stdout) as Array<{ state?: unknown; State?: unknown }>;
      if (!Array.isArray(parsed)) return [];
      return parsed
        .map((machine) => machine.state ?? machine.State)
        .filter((state): state is string => typeof state === "string");
    } catch {
      return [];
    }
  }

  private hasSecret(stdout: string, name: string): boolean {
    try {
      const parsed = JSON.parse(stdout) as Array<{ Name?: unknown; name?: unknown }>;
      if (Array.isArray(parsed)) {
        return parsed.some((secret) => secret.Name === name || secret.name === name);
      }
    } catch {
      // Fall back to substring check for older flyctl/plain-text output.
    }
    return stdout.includes(name);
  }

  private telegramGetMeProbeCommand(): string {
    return "sh -lc 'curl -sf --max-time 10 \"https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe\" >/dev/null 2>&1'";
  }
}
