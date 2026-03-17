import type { DestroyRunnerPort } from "../ports/destroy-runner.port.js";

export type DestroyDeploymentResult =
  | { kind: "ok" }
  | { kind: "already_absent" }
  | { kind: "failed"; error: string };

export interface DestroyIO {
  stdout: { write: (s: string) => void };
  stderr: { write: (s: string) => void };
}

export class DestroyDeploymentUseCase {
  constructor(private readonly runner: DestroyRunnerPort) {}

  async execute(appName: string, io: DestroyIO): Promise<DestroyDeploymentResult> {
    // Telegram cleanup — fail-open: errors are swallowed
    try {
      await this.runner.telegramLogout(appName);
    } catch {
      // fail-open: continue even if telegram logout fails
    }

    await this.runner.cleanupVolumes(appName);

    const destroyResult = await this.runner.destroyApp(appName);
    if (!destroyResult.ok) {
      if (destroyResult.reason === "not_found") {
        await this.runner.removeConfig(appName);
        io.stderr.write(`[success] Fly app '${appName}' was already absent; cleaned local config\n`);
        return { kind: "already_absent" };
      }

      const error = destroyResult.error ?? `Failed to destroy '${appName}'`;
      io.stderr.write(`[error] ${error}\n`);
      return { kind: "failed", error };
    }

    await this.runner.removeConfig(appName);
    io.stderr.write(`[success] Destroyed ${appName}\n`);
    return { kind: "ok" };
  }
}
