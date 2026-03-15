import type { DestroyRunnerPort } from "../ports/destroy-runner.port.js";

export type DestroyDeploymentResult =
  | { kind: "ok" }
  | { kind: "not_found" }
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
      io.stderr.write(`[error] App '${appName}' not found\n`);
      return { kind: "not_found" };
    }

    await this.runner.removeConfig(appName);
    io.stderr.write(`[success] Destroyed ${appName}\n`);
    return { kind: "ok" };
  }
}
