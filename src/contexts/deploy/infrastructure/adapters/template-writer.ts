import type { DeployConfig } from "../../application/ports/deploy-wizard.port.js";

const DEFAULT_VM_MEMORY_BY_SIZE: Record<string, string> = {
  "shared-cpu-1x": "256",
  "shared-cpu-2x": "512",
  "shared-cpu-4x": "2048",
  "shared-cpu-6x": "4096",
  "shared-cpu-8x": "8192",
  "performance-1x": "2048",
  "performance-2x": "4096",
  "performance-4x": "8192",
  "performance-8x": "16384"
};

export class TemplateWriter {
  async createBuildContext(config: DeployConfig, buildDir: string, opts?: { update?: boolean }): Promise<void> {
    const { copyFile, mkdir, readFile, writeFile } = await import("node:fs/promises");
    const { dirname, join } = await import("node:path");
    const { fileURLToPath } = await import("node:url");

    await mkdir(buildDir, { recursive: true });

    const templateDir = join(dirname(fileURLToPath(import.meta.url)), "../../../../../templates");
    const isUpdate = opts?.update ?? false;
    const dockerfileName = isUpdate ? "Dockerfile.update.template" : "Dockerfile.template";
    const dockerfileTemplate = await readFile(join(templateDir, dockerfileName), "utf8");
    const flyTomlTemplate = await readFile(join(templateDir, "fly.toml.template"), "utf8");
    const entrypointTemplate = join(templateDir, "entrypoint.sh");
    const supervisorTemplate = join(templateDir, "gateway-supervisor.sh");
    const sitecustomizeTemplate = join(templateDir, "sitecustomize.py");
    const compatPolicy = await this.readCompatibilityPolicyVersion();
    const vmMemory = this.resolveVmMemory(config.vmSize);

    const dockerfile = this.replaceAll(dockerfileTemplate, {
      HERMES_VERSION: config.hermesRef,
      HERMES_CHANNEL: config.channel,
      HERMES_COMPAT_POLICY: compatPolicy
    });
    await writeFile(join(buildDir, "Dockerfile"), dockerfile, "utf8");

    const flyToml = this.replaceAll(flyTomlTemplate, {
      APP_NAME: config.appName,
      REGION: config.region,
      VM_SIZE: config.vmSize,
      VM_MEMORY: vmMemory,
      VOLUME_NAME: "hermes_data",
      VOLUME_SIZE: String(config.volumeSize)
    });
    await writeFile(join(buildDir, "fly.toml"), flyToml, "utf8");
    await copyFile(entrypointTemplate, join(buildDir, "entrypoint.sh"));
    await copyFile(supervisorTemplate, join(buildDir, "gateway-supervisor.sh"));
    await copyFile(sitecustomizeTemplate, join(buildDir, "sitecustomize.py"));
  }

  private replaceAll(template: string, replacements: Record<string, string>): string {
    let rendered = template;
    for (const [key, value] of Object.entries(replacements)) {
      rendered = rendered.replaceAll(`{{${key}}}`, value);
    }
    return rendered;
  }

  private resolveVmMemory(vmSize: string): string {
    return DEFAULT_VM_MEMORY_BY_SIZE[vmSize] ?? "512";
  }

  private async readCompatibilityPolicyVersion(): Promise<string> {
    const { readFile } = await import("node:fs/promises");
    const { dirname, join } = await import("node:path");
    const { fileURLToPath } = await import("node:url");

    const snapshotPath = join(dirname(fileURLToPath(import.meta.url)), "../../../../../data/reasoning-snapshot.json");
    try {
      const raw = await readFile(snapshotPath, "utf8");
      const parsed = JSON.parse(raw) as { policy_version?: unknown };
      const value = String(parsed.policy_version ?? "").trim();
      return value.length > 0 ? value : "unknown";
    } catch {
      return "unknown";
    }
  }
}
