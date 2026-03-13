import { readCurrentApp } from "../contexts/runtime/infrastructure/adapters/current-app-config.js";

interface ResolveAppOptions {
  env?: NodeJS.ProcessEnv;
}

/**
 * Mirrors bash config_resolve_app semantics exactly.
 * Resolution order:
 *   1. -a APP from args (last occurrence wins)
 *   2. current_app from config.yaml
 *   3. null
 */
export async function resolveApp(args: string[], options: ResolveAppOptions = {}): Promise<string | null> {
  let appName: string | null = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "-a") {
      const next = args[i + 1];
      if (typeof next === "string" && next.length > 0 && !next.startsWith("-")) {
        appName = next;
        i++;
      }
      // -a without a value: continue (falls through to current_app)
    }
    // all other args are ignored
  }

  if (appName !== null) {
    return appName;
  }

  return readCurrentApp({ env: options.env });
}
