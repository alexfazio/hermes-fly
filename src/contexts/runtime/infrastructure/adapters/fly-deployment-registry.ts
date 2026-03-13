import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { FlyctlPort } from "../../../../adapters/flyctl.js";
import type {
  DeploymentListRow,
  DeploymentRegistryPort
} from "../../application/ports/deployment-registry.port.js";

interface ConfigEntry {
  name: string;
  region: string | null;
}

interface FlyDeploymentRegistryOptions {
  flyctl: FlyctlPort;
  env?: NodeJS.ProcessEnv;
}

export class FlyDeploymentRegistry implements DeploymentRegistryPort {
  private readonly flyctl: FlyctlPort;
  private readonly env: NodeJS.ProcessEnv;

  constructor(options: FlyDeploymentRegistryOptions) {
    this.flyctl = options.flyctl;
    this.env = options.env ?? process.env;
  }

  async listDeployments(): Promise<DeploymentListRow[]> {
    const configDir = resolveConfigDir(this.env);
    const configPath = join(configDir, "config.yaml");
    const configContent = await safeReadText(configPath);
    if (configContent === null) {
      return [];
    }

    const entries = parseConfigEntries(configContent);
    const rows: DeploymentListRow[] = [];

    for (const entry of entries) {
      const platform = await resolvePlatform(configDir, entry.name);
      const machine = await resolveMachine(this.flyctl, entry.name);

      rows.push({
        appName: truncate(entry.name, 26),
        region: entry.region ?? "?",
        platform,
        machine
      });
    }

    return rows;
  }
}

export function resolveConfigDir(env: NodeJS.ProcessEnv): string {
  const configDir = env.HERMES_FLY_CONFIG_DIR;
  if (typeof configDir === "string" && configDir.length > 0) {
    return normalizeConfigDir(configDir);
  }

  const home = env.HOME ?? "";
  if (home.length > 0) {
    return join(home, ".hermes-fly");
  }

  return join("/", ".hermes-fly");
}

function normalizeConfigDir(configDir: string): string {
  const normalized = join(configDir, ".");
  return normalized === "." ? "" : normalized;
}

async function safeReadText(path: string): Promise<string | null> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return null;
  }
}

function parseConfigEntries(configContent: string): ConfigEntry[] {
  const entries: ConfigEntry[] = [];
  let current: ConfigEntry | null = null;

  for (const line of configContent.split(/\r?\n/)) {
    const nameMatch = line.match(/^  - name:[ \t]*(.+)$/);
    if (nameMatch) {
      const rawName = nameMatch[1].trim();
      if (isSafeAppName(rawName)) {
        current = {
          name: rawName,
          region: null
        };
        entries.push(current);
      } else {
        current = null;
      }
      continue;
    }

    const regionMatch = line.match(/^    region:[ \t]*(.*)$/);
    if (regionMatch && current !== null) {
      const region = regionMatch[1].trim();
      current.region = region.length > 0 ? region : null;
    }
  }

  return entries;
}

export function isSafeAppName(value: string): boolean {
  return /^[a-zA-Z0-9._-]+$/.test(value);
}

async function resolvePlatform(configDir: string, appName: string): Promise<string> {
  const deployPath = join(configDir, "deploys", `${appName}.yaml`);
  const deployContent = await safeReadText(deployPath);
  if (deployContent === null) {
    return "-";
  }

  const platform = parseMessagingPlatform(deployContent);
  return platform ?? "-";
}

function parseMessagingPlatform(deployContent: string): string | null {
  const lines = deployContent.split(/\r?\n/);
  let inMessagingSection = false;
  let messagingIndent = 0;

  for (const line of lines) {
    const messagingMatch = line.match(/^(\s*)messaging:\s*$/);
    if (messagingMatch) {
      inMessagingSection = true;
      messagingIndent = messagingMatch[1].length;
      continue;
    }

    if (!inMessagingSection) {
      continue;
    }

    const trimmed = line.trim();
    if (trimmed.length === 0) {
      continue;
    }

    const indent = leadingWhitespace(line).length;
    if (indent <= messagingIndent) {
      inMessagingSection = false;
      continue;
    }

    const platformMatch = line.match(/^\s*platform:\s*(.+)\s*$/);
    if (platformMatch) {
      const platform = platformMatch[1].trim();
      return platform.length > 0 ? platform : null;
    }
  }

  return null;
}

function leadingWhitespace(line: string): string {
  const match = line.match(/^\s*/);
  return match ? match[0] : "";
}

async function resolveMachine(flyctl: FlyctlPort, appName: string): Promise<string> {
  try {
    const machine = await flyctl.getMachineState(appName);
    if (typeof machine === "string" && machine.length > 0) {
      return machine;
    }
  } catch {
    // Runtime lookup failures intentionally degrade to placeholder value.
  }

  return "?";
}

function truncate(value: string, maxLength: number): string {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength - 3)}...`;
}
