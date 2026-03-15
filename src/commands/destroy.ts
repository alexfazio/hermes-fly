import { DestroyDeploymentUseCase } from "../contexts/release/application/use-cases/destroy-deployment.js";
import type { DestroyRunnerPort } from "../contexts/release/application/ports/destroy-runner.port.js";
import { FlyDestroyRunner } from "../contexts/release/infrastructure/adapters/fly-destroy-runner.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { resolveApp } from "./resolve-app.js";

export interface DestroyCommandOptions {
  runner?: DestroyRunnerPort;
  stdout?: { write: (s: string) => void };
  stderr?: { write: (s: string) => void };
  /** Inject confirmation string for testing; if absent reads from process.stdin */
  confirmationInput?: string;
  /** Inject a pre-resolved app name (bypasses -a / config lookup) */
  appName?: string;
  /** Inject available apps for interactive selection (empty = error in production path) */
  availableApps?: string[];
  env?: NodeJS.ProcessEnv;
}

function parseForce(args: string[]): boolean {
  return args.includes("--force") || args.includes("-f");
}

async function readLineFromStdin(): Promise<string> {
  return new Promise((resolve) => {
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.once("data", (chunk: string) => {
      input = chunk.split("\n")[0].trim();
      resolve(input);
    });
    process.stdin.resume();
  });
}

export async function runDestroyCommand(
  args: string[],
  options: DestroyCommandOptions = {}
): Promise<number> {
  const stdout = options.stdout ?? process.stdout;
  const stderr = options.stderr ?? process.stderr;
  const force = parseForce(args);

  const runner: DestroyRunnerPort =
    options.runner ?? new FlyDestroyRunner(new NodeProcessRunner(), options.env);

  // Resolve app name
  let appName = options.appName ?? null;
  if (appName === null) {
    appName = await resolveApp(args, { env: options.env });
  }

  // No app resolved — error
  if (appName === null) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  // Confirmation (unless --force)
  if (!force) {
    stdout.write(`Are you sure you want to destroy ${appName}? Type 'yes' to confirm: `);
    const confirmInput =
      options.confirmationInput !== undefined
        ? options.confirmationInput
        : await readLineFromStdin();
    if (confirmInput !== "yes") {
      stdout.write("Aborted.\n");
      return 1;
    }
  }

  const useCase = new DestroyDeploymentUseCase(runner);
  const io = { stdout, stderr };
  const result = await useCase.execute(appName, io);

  switch (result.kind) {
    case "ok":
      return 0;
    case "not_found":
      return 4;
    case "failed":
      return 1;
  }
}
