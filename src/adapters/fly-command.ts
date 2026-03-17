import { constants } from "node:fs";
import { join } from "node:path";

export async function resolveFlyCommand(env?: NodeJS.ProcessEnv): Promise<string> {
  const explicit = (env?.HERMES_FLY_FLYCTL_BIN ?? "").trim();
  if (explicit.length > 0 && await isExecutable(explicit)) {
    return explicit;
  }

  const home = env?.HOME ?? process.env.HOME;
  if (home) {
    const installedFlyPath = join(home, ".fly", "bin", "fly");
    if (await isExecutable(installedFlyPath)) {
      return installedFlyPath;
    }
  }

  return "fly";
}

async function isExecutable(path: string): Promise<boolean> {
  const { access } = await import("node:fs/promises");
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}
