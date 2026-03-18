import { readCurrentApp } from "../contexts/runtime/infrastructure/adapters/current-app-config.js";

interface ResolveAppOptions {
  env?: NodeJS.ProcessEnv;
}

interface ParsedAppArgs {
  explicitFlagSeen: boolean;
  explicitApps: string[];
  hasMissingExplicitValue: boolean;
  firstPositional: string | null;
  positionalApps: string[];
}

/**
 * Resolves the target app name from CLI args and config.
 * Resolution order:
 *   1. If -a appears and a following token exists (any token, including hyphen-prefixed):
 *      treat that token as the explicit app name. Last -a wins.
 *   2. If -a appears but has no following token: return null.
 *   3. If no -a appears and a first positional argument exists, use it as the app name.
 *   4. Otherwise return current_app from config.yaml (or null if absent).
 */
export async function resolveApp(args: string[], options: ResolveAppOptions = {}): Promise<string | null> {
  const parsed = parseAppArgs(args);

  if (parsed.explicitFlagSeen) {
    if (parsed.hasMissingExplicitValue || parsed.explicitApps.length === 0) {
      return null;
    }
    return parsed.explicitApps[parsed.explicitApps.length - 1] ?? null;
  }

  if (parsed.firstPositional !== null) {
    return parsed.firstPositional;
  }

  return readCurrentApp({ env: options.env });
}

export async function resolveApps(args: string[], options: ResolveAppOptions = {}): Promise<string[] | null> {
  const parsed = parseAppArgs(args);

  if (parsed.explicitFlagSeen) {
    if (parsed.hasMissingExplicitValue || parsed.explicitApps.length === 0) {
      return null;
    }
    return dedupeApps(parsed.explicitApps);
  }

  if (parsed.positionalApps.length > 0) {
    return dedupeApps(parsed.positionalApps);
  }

  const currentApp = await readCurrentApp({ env: options.env });
  return currentApp ? [currentApp] : [];
}

function parseAppArgs(args: string[]): ParsedAppArgs {
  let explicitFlagSeen = false;
  let hasMissingExplicitValue = false;
  let firstPositional: string | null = null;
  const explicitApps: string[] = [];
  const positionalApps: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "-a") {
      explicitFlagSeen = true;
      const next = args[index + 1];
      if (typeof next === "string" && next.length > 0) {
        explicitApps.push(next);
        index += 1;
      } else {
        hasMissingExplicitValue = true;
      }
      continue;
    }

    if (!arg.startsWith("-")) {
      if (firstPositional === null) {
        firstPositional = arg;
      }
      positionalApps.push(arg);
    }
  }

  return {
    explicitFlagSeen,
    explicitApps,
    hasMissingExplicitValue,
    firstPositional,
    positionalApps,
  };
}

function dedupeApps(apps: string[]): string[] {
  return [...new Set(apps)];
}

/**
 * Simple resolver for commands that just need the current target app.
 * Returns null if no app can be determined.
 */
export async function resolveTargetApp(options: ResolveAppOptions = {}): Promise<string | null> {
  return readCurrentApp({ env: options.env });
}
