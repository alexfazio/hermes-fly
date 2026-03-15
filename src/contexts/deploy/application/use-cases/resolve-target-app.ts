import type { ConfigRepositoryPort } from "../ports/config-repository.port.js";

/**
 * Resolves the target app name from CLI args and config.
 * Resolution order:
 *   1. If -a never appears: return current_app from config port (or null if absent).
 *   2. If -a appears and a following token exists: treat that token as the explicit app name. Last -a wins.
 *   3. If -a appears but has no following token: return null.
 */
export class ResolveTargetAppUseCase {
  constructor(private readonly configRepo: ConfigRepositoryPort) {}

  async execute(args: string[]): Promise<string | null> {
    let seenExplicitFlag = false;
    let appName: string | null = null;

    for (let i = 0; i < args.length; i++) {
      if (args[i] === "-a") {
        seenExplicitFlag = true;
        const next = args[i + 1];
        if (typeof next === "string" && next.length > 0) {
          appName = next;
          i++;
        } else {
          appName = null;
        }
      }
    }

    if (seenExplicitFlag) {
      return appName;
    }

    return this.configRepo.readCurrentApp();
  }
}
