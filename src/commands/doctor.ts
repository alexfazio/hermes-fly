import { RunDoctorUseCase } from "../contexts/diagnostics/application/use-cases/run-doctor.js";
import type { DoctorChecksPort } from "../contexts/diagnostics/application/ports/doctor-checks.port.js";
import { FlyDoctorChecks } from "../contexts/diagnostics/infrastructure/adapters/fly-doctor-checks.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { resolveApp } from "./resolve-app.js";

export interface DoctorCommandOptions {
  checks?: DoctorChecksPort;
  stderr?: { write: (s: string) => void };
  /** Pre-resolved app name or null to indicate no app */
  appName?: string | null;
  env?: NodeJS.ProcessEnv;
}

function formatCheck(key: string, pass: boolean, message: string): string {
  const label = pass ? "[PASS]" : "[FAIL]";
  return `${label} ${key}: ${message}\n`;
}

export async function runDoctorCommand(
  args: string[],
  options: DoctorCommandOptions = {}
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

  const checks: DoctorChecksPort =
    options.checks ?? new FlyDoctorChecks(new NodeProcessRunner(), appName, options.env);

  const useCase = new RunDoctorUseCase(checks);
  const result = await useCase.execute(appName);

  for (const check of result.checks) {
    stderr.write(formatCheck(check.key, check.pass, check.message));
  }
  stderr.write(`[${result.allPassed ? "PASS" : "FAIL"}] summary: ${result.passCount} passed, ${result.failCount} failed\n`);

  return result.allPassed ? 0 : 1;
}
