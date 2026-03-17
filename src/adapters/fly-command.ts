import { constants } from "node:fs";
import { delimiter } from "node:path";
import { join } from "node:path";

export async function resolveFlyCommand(env?: NodeJS.ProcessEnv): Promise<string> {
  const explicit = (env?.HERMES_FLY_FLYCTL_BIN ?? "").trim();
  if (explicit.length > 0 && await isExecutable(explicit)) {
    return explicit;
  }

  const pathResolved = await findFlyOnPath(env?.PATH ?? process.env.PATH);
  if (pathResolved !== null) {
    return pathResolved;
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

async function findFlyOnPath(pathValue: string | undefined): Promise<string | null> {
  if (!pathValue) {
    return null;
  }

  for (const entry of pathValue.split(delimiter)) {
    const dir = entry.trim();
    if (dir.length === 0) {
      continue;
    }
    const candidate = join(dir, "fly");
    if (await isExecutable(candidate)) {
      return candidate;
    }
  }

  return null;
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
