import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { resolveConfigDir, isSafeAppName } from "./fly-deployment-registry.js";

interface ReadCurrentAppOptions {
  env?: NodeJS.ProcessEnv;
}

export async function readCurrentApp(options: ReadCurrentAppOptions = {}): Promise<string | null> {
  const env = options.env ?? process.env;
  const configDir = resolveConfigDir(env);
  const configPath = join(configDir, "config.yaml");

  let content: string;
  try {
    content = await readFile(configPath, "utf8");
  } catch {
    return null;
  }

  for (const line of content.split(/\r?\n/)) {
    const match = line.match(/^current_app:\s*(.*)\s*$/);
    if (match) {
      const value = match[1].trim();
      if (value.length === 0) {
        return null;
      }
      if (!isSafeAppName(value)) {
        return null;
      }
      return value;
    }
  }

  return null;
}
