import { NodeProcessRunner } from "../adapters/process.js";
import { ExecuteAgentCommandUseCase } from "../contexts/runtime/application/use-cases/execute-agent-command.js";
import { FlyRemoteSession } from "../contexts/runtime/infrastructure/adapters/fly-remote-session.js";
import { resolveRemoteCommandInvocation } from "./resolve-remote-command.js";

interface AgentCommandOptions {
  stderr?: Pick<NodeJS.WriteStream, "write">;
  useCase?: ExecuteAgentCommandUseCase;
  env?: NodeJS.ProcessEnv;
}

export async function runAgentCommand(args: string[], options: AgentCommandOptions = {}): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const env = options.env ?? process.env;
  const useCase = options.useCase ?? buildUseCase(env);

  const invocation = await resolveRemoteCommandInvocation(args, { env });
  if (invocation.appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  if (invocation.commandArgs.length === 0) {
    stderr.write("[error] No Hermes subcommand specified. Use 'hermes-fly console -a APP' for an interactive session.\n");
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

function buildUseCase(env: NodeJS.ProcessEnv): ExecuteAgentCommandUseCase {
  const runner = new NodeProcessRunner();
  const port = new FlyRemoteSession(runner, env);
  return new ExecuteAgentCommandUseCase(port);
}

function isFlyCliMissing(message: string): boolean {
  return message.includes("spawn fly ENOENT") || message.includes("ENOENT");
}
