import { NodeProcessRunner, type ForegroundProcessRunner } from "../adapters/process.js";
import { UpdateDeploymentUseCase } from "../contexts/deploy/application/use-cases/update-deployment.js";
import { FlyUpdateRunner } from "../contexts/deploy/infrastructure/adapters/fly-update-runner.js";
import { FlyDeployWizard } from "../contexts/deploy/infrastructure/adapters/fly-deploy-wizard.js";
import { resolveTargetApp } from "./resolve-app.js";

export interface UpdateCommandOptions {
  stdout?: { write: (s: string) => void };
  stderr?: { write: (s: string) => void };
  env?: NodeJS.ProcessEnv;
}

function parseUpdateArgs(args: string[]): { channel: string; appName?: string } {
  let channel = "stable";
  let appName: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--channel" && i + 1 < args.length) {
      channel = args[++i];
    } else if ((args[i] === "-a" || args[i] === "--app") && i + 1 < args.length) {
      appName = args[++i];
    }
  }

  return { channel, appName };
}

export async function runUpdateCommand(
  args: string[],
  options: UpdateCommandOptions = {}
): Promise<number> {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const { channel, appName: explicitApp } = parseUpdateArgs(args);

  // Validate channel
  if (!["stable", "preview", "edge"].includes(channel)) {
    stderr.write(`[error] Invalid channel: ${channel}. Use: stable, preview, or edge\n`);
    return 1;
  }

  // Resolve target app
  let appName: string | null = explicitApp ?? null;
  if (!appName) {
    appName = await resolveTargetApp({ env: options.env });
  }

  if (!appName) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  // Run update
  const runner = new FlyUpdateRunner(new NodeProcessRunner(), options.env);
  const wizard = new FlyDeployWizard(options.env);
  const useCase = new UpdateDeploymentUseCase(runner, wizard, options.env);

  const result = await useCase.execute(
    { appName, channel: channel as "stable" | "preview" | "edge" },
    stderr,
    stdout
  );

  return result.kind === "ok" ? 0 : 1;
}
