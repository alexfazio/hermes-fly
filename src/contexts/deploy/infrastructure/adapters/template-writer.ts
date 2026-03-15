import type { DeployConfig } from "../../application/ports/deploy-wizard.port.js";

export class TemplateWriter {
  async createBuildContext(config: DeployConfig, buildDir: string): Promise<void> {
    const { writeFile, mkdir } = await import("node:fs/promises");
    const { join } = await import("node:path");

    await mkdir(buildDir, { recursive: true });

    const dockerfile = `FROM ghcr.io/anthropics/hermes-agent:${config.hermesRef}
ENV HERMES_DEPLOY_CHANNEL=${config.channel}
`;
    await writeFile(join(buildDir, "Dockerfile"), dockerfile, "utf8");

    const flyToml = `app = "${config.appName}"
primary_region = "${config.region}"

[build]
  dockerfile = "Dockerfile"

[vm]
  size = "${config.vmSize}"

[mounts]
  source = "hermes_data"
  destination = "/data"
`;
    await writeFile(join(buildDir, "fly.toml"), flyToml, "utf8");
  }
}
