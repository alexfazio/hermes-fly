import { ResumeDeploymentChecksUseCase } from "../contexts/deploy/application/use-cases/resume-deployment-checks.js";
import type { ResumeChecksPort } from "../contexts/deploy/application/ports/resume-checks.port.js";
import { FlyResumeReader } from "../contexts/deploy/infrastructure/adapters/fly-resume-reader.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { resolveApp } from "./resolve-app.js";

export interface ResumeCommandOptions {
  checks?: ResumeChecksPort;
  stderr?: { write: (s: string) => void };
  /** Pre-resolved app name or null to indicate no app */
  appName?: string | null;
  env?: NodeJS.ProcessEnv;
}

export async function runResumeCommand(
  args: string[],
  options: ResumeCommandOptions = {}
): Promise<number> {
  const stderr = options.stderr ?? process.stderr;

  // Resolve app name
  let appName: string | null;
  if ("appName" in options) {
    appName = options.appName ?? null;
  } else {
    appName = await resolveApp(args, { env: options.env });
  }

  if (appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  const checks: ResumeChecksPort =
    options.checks ?? new FlyResumeReader(new NodeProcessRunner(), options.env);

  const useCase = new ResumeDeploymentChecksUseCase(checks);
  const result = await useCase.execute(appName, stderr);

  return result.kind === "ok" ? 0 : 1;
}
