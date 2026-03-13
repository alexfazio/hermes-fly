import { FlyctlAdapter } from "../adapters/flyctl.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { ShowStatusUseCase } from "../contexts/runtime/application/use-cases/show-status.js";
import { FlyStatusReader } from "../contexts/runtime/infrastructure/adapters/fly-status-reader.js";
import { resolveApp } from "./resolve-app.js";

interface StatusCommandOptions {
  stderr?: Pick<NodeJS.WriteStream, "write">;
  stdout?: Pick<NodeJS.WriteStream, "write">;
  useCase?: ShowStatusUseCase;
  env?: NodeJS.ProcessEnv;
}

export async function runStatusCommand(args: string[], options: StatusCommandOptions = {}): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const stdout = options.stdout ?? process.stdout;
  const env = options.env ?? process.env;
  const useCase = options.useCase ?? buildUseCase();

  const appName = await resolveApp(args, { env });
  if (appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  const result = await useCase.execute(appName);

  if (result.kind === "error") {
    stderr.write(`[error] Failed to get status for app '${appName}': ${result.message}\n`);
    return 1;
  }

  const { details } = result;
  stderr.write(`[info] App:     ${details.appName}\n`);
  stderr.write(`[info] Status:  ${details.status ?? "unknown"}\n`);
  stderr.write(`[info] Machine: ${details.machine ?? "unknown"}\n`);
  stderr.write(`[info] Region:  ${details.region ?? "unknown"}\n`);
  if (details.hostname !== null && details.hostname.length > 0) {
    stderr.write(`✓ URL:     https://${details.hostname}\n`);
  }

  void stdout;
  return 0;
}

function buildUseCase(): ShowStatusUseCase {
  const runner = new NodeProcessRunner();
  const flyctl = new FlyctlAdapter(runner);
  const reader = new FlyStatusReader(flyctl);
  return new ShowStatusUseCase(reader);
}
