import { NodeProcessRunner } from "../adapters/process.js";
import { ExecuteRemoteCommandUseCase } from "../contexts/runtime/application/use-cases/execute-remote-command.js";
import { FlyRemoteSession } from "../contexts/runtime/infrastructure/adapters/fly-remote-session.js";
import { resolveRemoteCommandInvocation } from "./resolve-remote-command.js";

interface ExecCommandOptions {
  stderr?: Pick<NodeJS.WriteStream, "write">;
  useCase?: ExecuteRemoteCommandUseCase;
  env?: NodeJS.ProcessEnv;
}

export async function runExecCommand(args: string[], options: ExecCommandOptions = {}): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const env = options.env ?? process.env;
  const useCase = options.useCase ?? buildUseCase(env);

  const invocation = await resolveRemoteCommandInvocation(args, { env });
  if (invocation.appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  if (invocation.commandArgs.length === 0) {
    stderr.write("[error] No remote command specified. Use '-- <command...>' or pass the command directly.\n");
    return 1;
  }

  const result = await useCase.execute(invocation.appName, invocation.commandArgs);
  if (result.kind === "error") {
    if (isFlyCliMissing(result.message)) {
      stderr.write("[error] Fly.io CLI not found. Install flyctl and retry.\n");
    } else {
      stderr.write(`[error] ${result.message}\n`);
    }
    return 1;
  }

  return 0;
}

function buildUseCase(env: NodeJS.ProcessEnv): ExecuteRemoteCommandUseCase {
  const runner = new NodeProcessRunner();
  const port = new FlyRemoteSession(runner, env);
  return new ExecuteRemoteCommandUseCase(port);
}

function isFlyCliMissing(message: string): boolean {
  return message.includes("spawn fly ENOENT") || message.includes("ENOENT");
}
