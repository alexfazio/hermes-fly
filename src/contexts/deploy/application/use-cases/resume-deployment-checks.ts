import type { ResumeChecksPort } from "../ports/resume-checks.port.js";

export type ResumeDeploymentResult =
  | { kind: "ok" }
  | { kind: "failed"; error: string };

export class ResumeDeploymentChecksUseCase {
  constructor(private readonly checks: ResumeChecksPort) {}

  async execute(
    appName: string,
    stderr: { write: (s: string) => void }
  ): Promise<ResumeDeploymentResult> {
    stderr.write(`Resuming deployment checks for ${appName}...\n`);

    const status = await this.checks.fetchStatus(appName);
    if (!status.ok) {
      stderr.write(`[error] Could not fetch status for '${appName}'\n`);
      return { kind: "failed", error: `Could not fetch status for '${appName}'` };
    }

    const running = await this.checks.checkMachineRunning(appName);
    if (!running) {
      stderr.write(`[error] Machine not running for '${appName}'\n`);
      if (status.region) {
        await this.checks.saveApp(appName, status.region);
      }
      return { kind: "failed", error: "Machine not running" };
    }

    if (status.region) {
      await this.checks.saveApp(appName, status.region);
    }

    stderr.write(`Resume complete\n`);
    return { kind: "ok" };
  }
}
