import { readCurrentApp } from "../contexts/runtime/infrastructure/adapters/current-app-config.js";

interface ResolveRemoteCommandOptions {
  env?: NodeJS.ProcessEnv;
}

export interface ResolvedRemoteCommandInvocation {
  appName: string | null;
  commandArgs: string[];
  missingExplicitApp: boolean;
}

export async function resolveRemoteCommandInvocation(
  args: string[],
  options: ResolveRemoteCommandOptions = {}
): Promise<ResolvedRemoteCommandInvocation> {
  const env = options.env;
  let explicitApp: string | null = null;
  let explicitFlagSeen = false;
  let missingExplicitApp = false;
  const remaining: string[] = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "-a") {
      explicitFlagSeen = true;
      const next = args[index + 1];
      if (typeof next === "string" && next.length > 0) {
        explicitApp = next;
        index += 1;
      } else {
        missingExplicitApp = true;
      }
      continue;
    }
    remaining.push(arg);
  }

  if (explicitFlagSeen) {
    return {
      appName: missingExplicitApp ? null : explicitApp,
      commandArgs: stripLeadingSeparator(remaining),
      missingExplicitApp,
    };
  }

  const currentApp = await readCurrentApp({ env });
  if (currentApp) {
    return { appName: currentApp, commandArgs: stripLeadingSeparator(args), missingExplicitApp: false };
  }

  const [appName, ...commandArgs] = remaining;
  return {
    appName: appName ?? null,
    commandArgs: stripLeadingSeparator(commandArgs),
    missingExplicitApp: false,
  };
}

function stripLeadingSeparator(args: string[]): string[] {
  if (args[0] === "--") {
    return args.slice(1);
  }

  return args;
}
