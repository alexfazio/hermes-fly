import { readCurrentApp } from "../contexts/runtime/infrastructure/adapters/current-app-config.js";

interface ResolveAppOptions {
  env?: NodeJS.ProcessEnv;
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
  let seenExplicitFlag = false;
  let appName: string | null = null;
  let firstPositional: string | null = null;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "-a") {
      seenExplicitFlag = true;
      const next = args[i + 1];
      if (typeof next === "string" && next.length > 0) {
        appName = next;
        i++;
      } else {
        // -a with no following token: explicit flag present but value missing
        appName = null;
      }
      continue;
    }

    if (firstPositional === null && !arg.startsWith("-")) {
      firstPositional = arg;
    }
  }

  if (seenExplicitFlag) {
    return appName;
  }

  if (firstPositional !== null) {
    return firstPositional;
  }

  return readCurrentApp({ env: options.env });
}
