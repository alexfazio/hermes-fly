import { FlyctlAdapter } from "../adapters/flyctl.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { ShowLogsUseCase } from "../contexts/runtime/application/use-cases/show-logs.js";
import { FlyLogsReader } from "../contexts/runtime/infrastructure/adapters/fly-logs-reader.js";
import { resolveApp } from "./resolve-app.js";

interface LogsCommandOptions {
  stderr?: Pick<NodeJS.WriteStream, "write">;
  stdout?: Pick<NodeJS.WriteStream, "write">;
  useCase?: ShowLogsUseCase;
  env?: NodeJS.ProcessEnv;
}

export async function runLogsCommand(args: string[], options: LogsCommandOptions = {}): Promise<number> {
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

  if (result.exitCode !== 0) {
    stderr.write(`[error] Failed to fetch logs for app '${appName}'\n`);
    return 1;
  }

  if (result.stdout.length > 0) {
    stdout.write(result.stdout);
  }
  if (result.stderr.length > 0) {
    stderr.write(result.stderr);
  }

  return 0;
}

function buildUseCase(): ShowLogsUseCase {
  const runner = new NodeProcessRunner();
  const flyctl = new FlyctlAdapter(runner);
  const reader = new FlyLogsReader(flyctl);
  return new ShowLogsUseCase(reader);
}
