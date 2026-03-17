import { NodeProcessRunner } from "../adapters/process.js";
import { OpenConsoleUseCase } from "../contexts/runtime/application/use-cases/open-console.js";
import { FlyRemoteSession } from "../contexts/runtime/infrastructure/adapters/fly-remote-session.js";
import { readCurrentApp } from "../contexts/runtime/infrastructure/adapters/current-app-config.js";

interface ConsoleCommandOptions {
  stdout?: Pick<NodeJS.WriteStream, "write">;
  stderr?: Pick<NodeJS.WriteStream, "write">;
  useCase?: OpenConsoleUseCase;
  env?: NodeJS.ProcessEnv;
}

export async function runConsoleCommand(args: string[], options: ConsoleCommandOptions = {}): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const env = options.env ?? process.env;
  const useCase = options.useCase ?? buildUseCase(env);

  const invocation = await resolveConsoleInvocation(args, env);
  if (invocation.error) {
    stderr.write(`[error] ${invocation.error}\n`);
    return 1;
  }

  const { appName, hermesArgs, mode } = invocation;
  if (appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  const result = await useCase.execute(appName, mode, hermesArgs);
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

function buildUseCase(env: NodeJS.ProcessEnv): OpenConsoleUseCase {
  const runner = new NodeProcessRunner();
  const port = new FlyRemoteSession(runner, env);
  return new OpenConsoleUseCase(port);
}

async function resolveConsoleInvocation(
  args: string[],
  env: NodeJS.ProcessEnv
): Promise<{ appName: string | null; hermesArgs: string[]; mode: "agent" | "shell"; error?: string }> {
  let agentApp: string | null = null;
  let shellApp: string | null = null;
  let agentFlagSeen = false;
  let shellFlagSeen = false;
  const remaining: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "-a") {
      agentFlagSeen = true;
      const next = args[index + 1];
      if (typeof next === "string" && next.length > 0) {
        agentApp = next;
        index += 1;
      } else {
        agentApp = null;
      }
      continue;
    }
    if (arg === "-s") {
      shellFlagSeen = true;
      const next = args[index + 1];
      if (typeof next === "string" && next.length > 0) {
        shellApp = next;
        index += 1;
      } else {
        shellApp = null;
      }
      continue;
    }
    remaining.push(arg);
  }

  if (agentFlagSeen && shellFlagSeen) {
    return { appName: null, hermesArgs: [], mode: "agent", error: "Choose either -a for agent mode or -s for shell mode." };
  }

  if (shellFlagSeen) {
    if (remaining.length > 0) {
      return {
        appName: null,
        hermesArgs: [],
        mode: "shell",
        error: "Shell mode does not accept extra arguments. Use 'hermes-fly exec' or 'hermes-fly agent' instead.",
      };
    }
    return {
      appName: shellApp ?? await readCurrentApp({ env }),
      hermesArgs: [],
      mode: "shell",
    };
  }

  if (agentFlagSeen) {
    return { appName: agentApp, hermesArgs: remaining, mode: "agent" };
  }

  if (remaining.length > 0) {
    const [appName, ...hermesArgs] = remaining;
    return { appName, hermesArgs, mode: "agent" };
  }

  return { appName: await readCurrentApp({ env }), hermesArgs: [], mode: "agent" };
}

function isFlyCliMissing(message: string): boolean {
  return message.includes("spawn fly ENOENT") || message.includes("ENOENT");
}
