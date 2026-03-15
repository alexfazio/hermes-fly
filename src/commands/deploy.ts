import { RunDeployWizardUseCase } from "../contexts/deploy/application/use-cases/run-deploy-wizard.js";
import type { DeployWizardPort } from "../contexts/deploy/application/ports/deploy-wizard.port.js";

export interface DeployCommandOptions {
  wizard?: DeployWizardPort;
  stderr?: { write: (s: string) => void };
  env?: NodeJS.ProcessEnv;
}

function parseDeployArgs(args: string[]): { channel: string; autoInstall: boolean } {
  let channel = "stable";
  let autoInstall = true;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--channel" && i + 1 < args.length) {
      channel = args[++i];
    } else if (args[i] === "--no-auto-install") {
      autoInstall = false;
    }
  }

  return { channel, autoInstall };
}

export async function runDeployCommand(
  args: string[],
  options: DeployCommandOptions = {}
): Promise<number> {
  const stderr = options.stderr ?? process.stderr;
  const { channel, autoInstall } = parseDeployArgs(args);

  const wizard = options.wizard;
  if (!wizard) {
    // Check for fast-fail cases: --no-auto-install with missing fly
    if (!autoInstall) {
      const { execSync } = await import("node:child_process");
      try {
        execSync("which fly", { stdio: "ignore" });
      } catch {
        stderr.write("[error] 'fly' not found (auto-install disabled). Install manually and retry.\n");
        return 1;
      }
    }
    // Production path: interactive wizard not fully implemented yet
    stderr.write("[error] deploy: interactive wizard not available in this build\n");
    return 1;
  }

  const useCase = new RunDeployWizardUseCase(wizard);
  const result = await useCase.execute({ autoInstall, channel }, stderr);

  return result.kind === "ok" ? 0 : 1;
}
