import { FlyctlAdapter, type FlyctlPort } from "../adapters/flyctl.js";
import { NodeProcessRunner } from "../adapters/process.js";
import { DestroyDeploymentUseCase } from "../contexts/release/application/use-cases/destroy-deployment.js";
import type { DestroyRunnerPort } from "../contexts/release/application/ports/destroy-runner.port.js";
import { FlyDestroyRunner } from "../contexts/release/infrastructure/adapters/fly-destroy-runner.js";
import { TerminalQrCodeRenderer, type QrCodeRendererPort } from "../contexts/deploy/infrastructure/adapters/qr-code.js";
import {
  TELEGRAM_BOTFATHER_DELETEBOT_URL,
  telegramBotLink
} from "../contexts/messaging/infrastructure/adapters/telegram-links.js";
import {
  readSavedDeploymentEntries,
  readSavedDeploymentEntry,
} from "../contexts/runtime/infrastructure/adapters/fly-deployment-registry.js";
import { resolveApps } from "./resolve-app.js";

export interface DestroyCommandOptions {
  runner?: DestroyRunnerPort;
  flyctl?: Pick<FlyctlPort, "getTelegramBotIdentity" | "getMachineSummary">;
  qrRenderer?: QrCodeRendererPort;
  stdout?: { write: (s: string) => void };
  stderr?: { write: (s: string) => void };
  stdin?: {
    setEncoding: (encoding: BufferEncoding) => void;
    once: (event: "data", listener: (chunk: string) => void) => void;
    resume: () => void;
    pause: () => void;
  };
  /** Inject confirmation string for testing; if absent reads from process.stdin */
  confirmationInput?: string;
  /** Inject a pre-resolved app name (bypasses -a / config lookup) */
  appName?: string;
  /** Inject pre-resolved app names for batch destruction. */
  appNames?: string[];
  /** Inject available apps for interactive selection (empty = error in production path) */
  availableApps?: string[];
  env?: NodeJS.ProcessEnv;
}

type TelegramCleanupContext = {
  configured: boolean;
  username: string | null;
  directLink: string | null;
};

function parseForce(args: string[]): boolean {
  return args.includes("--force") || args.includes("-f");
}

async function readLineFromStdin(
  stdin: DestroyCommandOptions["stdin"] = process.stdin
): Promise<string> {
  return new Promise((resolve) => {
    let input = "";
    stdin.setEncoding("utf8");
    stdin.once("data", (chunk: string) => {
      input = chunk.split("\n")[0].trim();
      stdin.pause();
      resolve(input);
    });
    stdin.resume();
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

  let appNames = options.appNames ?? null;
  if (appNames === null) {
    if (options.appName) {
      appNames = [options.appName];
    } else {
      appNames = await resolveApps(args, { env: options.env });
    }
  }

  // No app resolved — error
  if (appNames === null || appNames.length === 0) {
    stderr.write("[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    return 1;
  }

  try {
    appNames = await resolveDestroyTargets(appNames, options);
  } catch (error) {
    if (isFlyCliMissing(error)) {
      stderr.write("[error] Fly.io CLI not found. Install flyctl and retry.\n");
      return 1;
    }
    throw error;
  }

  // Confirmation (unless --force)
  if (!force) {
    const prompt = appNames.length === 1
      ? `Are you sure you want to destroy ${appNames[0]}? Type 'yes' to confirm: `
      : `Are you sure you want to destroy ${appNames.length} apps (${appNames.join(", ")})? Type 'yes' to confirm: `;
    stdout.write(prompt);
    const confirmInput =
      options.confirmationInput !== undefined
        ? options.confirmationInput
        : await readLineFromStdin(options.stdin);
    if (confirmInput !== "yes") {
      stdout.write("Aborted.\n");
      return 1;
    }
  }

  const useCase = new DestroyDeploymentUseCase(runner);
  const io = { stdout, stderr };
  let hadFailure = false;

  for (const appName of appNames) {
    let telegramCleanup: TelegramCleanupContext | null = null;
    try {
      telegramCleanup = await resolveTelegramCleanupContext(appName, options);
    } catch (error) {
      if (isFlyCliMissing(error)) {
        stderr.write("[error] Fly.io CLI not found. Install flyctl and retry.\n");
        return 1;
      }
      throw error;
    }

    let result;
    try {
      result = await useCase.execute(appName, io);
    } catch (error) {
      if (isFlyCliMissing(error)) {
        stderr.write("[error] Fly.io CLI not found. Install flyctl and retry.\n");
        return 1;
      }
      throw error;
    }

    switch (result.kind) {
      case "ok":
      case "already_absent":
        if (telegramCleanup?.configured) {
          await writeTelegramDeletionGuidance(stdout, appName, telegramCleanup, options.qrRenderer);
        }
        break;
      case "failed":
        hadFailure = true;
        break;
      }
  }

  return hadFailure ? 1 : 0;
}

async function resolveTelegramCleanupContext(
  appName: string,
  options: DestroyCommandOptions
): Promise<TelegramCleanupContext> {
  const env = options.env ?? process.env;
  const savedEntry = await readSavedDeploymentEntry(appName, env);

  let configured = savedEntry?.platform === "telegram" || savedEntry?.telegramBotUsername !== null;
  let username = savedEntry?.telegramBotUsername ?? null;

  const flyctl =
    options.flyctl
    ?? (options.runner === undefined ? new FlyctlAdapter(new NodeProcessRunner()) : null);

  if (flyctl !== null) {
    try {
      const identity = await flyctl.getTelegramBotIdentity(appName);
      if (identity.configured) {
        configured = true;
      }
      if (identity.username) {
        username = identity.username;
      }
    } catch (error) {
      if (isFlyCliMissing(error)) {
        throw error;
      }
    }
  }

  return {
    configured,
    username,
    directLink: username ? telegramBotLink(username) : null
  };
}

async function resolveDestroyTargets(
  targets: string[],
  options: DestroyCommandOptions
): Promise<string[]> {
  const env = options.env ?? process.env;
  const savedEntries = await readSavedDeploymentEntries(env);
  if (savedEntries.length === 0) {
    return dedupeInOrder(targets);
  }

  const savedNames = new Set(savedEntries.map((entry) => entry.name));
  const unresolvedTargets = targets.filter((target) => !savedNames.has(target));
  if (unresolvedTargets.length === 0) {
    return dedupeInOrder(targets);
  }

  const flyctl =
    options.flyctl
    ?? (options.runner === undefined ? new FlyctlAdapter(new NodeProcessRunner()) : null);
  if (flyctl === null) {
    return dedupeInOrder(targets);
  }

  const machineToApp = new Map<string, string>();
  for (const entry of savedEntries) {
    const machine = await flyctl.getMachineSummary(entry.name);
    const machineId = machine.id?.trim();
    if (!machineId || !unresolvedTargets.includes(machineId)) {
      continue;
    }
    machineToApp.set(machineId, entry.name);
  }

  return dedupeInOrder(targets.map((target) => machineToApp.get(target) ?? target));
}

async function writeTelegramDeletionGuidance(
  stdout: { write: (s: string) => void },
  appName: string,
  cleanup: TelegramCleanupContext,
  qrRenderer?: QrCodeRendererPort
): Promise<void> {
  stdout.write(`\nTelegram bot cleanup for ${appName}\n`);
  stdout.write("Telegram does not document any Bot API method that permanently deletes a bot.\n");
  if (cleanup.username) {
    stdout.write(`Configured bot: @${cleanup.username}\n`);
  }
  if (cleanup.directLink) {
    stdout.write(`Bot link: ${cleanup.directLink}\n`);
  }
  stdout.write("To finish deleting the bot itself, open BotFather with /deletebot prefilled:\n");
  stdout.write(`${TELEGRAM_BOTFATHER_DELETEBOT_URL}\n`);
  stdout.write("Scan this QR code with your phone to open BotFather with /deletebot ready to send:\n\n");

  const renderer = qrRenderer ?? new TerminalQrCodeRenderer();
  try {
    const qr = await renderer.render(TELEGRAM_BOTFATHER_DELETEBOT_URL);
    stdout.write(`${qr}\n`);
  } catch {
    stdout.write("(QR code unavailable in this terminal. Use the direct link above.)\n\n");
  }

  stdout.write("If Telegram opens the chat without sending anything, tap Send to submit /deletebot.\n");
  if (cleanup.username) {
    stdout.write(`When BotFather asks which bot to delete, choose @${cleanup.username}.\n`);
  }
}

function isFlyCliMissing(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }

  const errWithCode = error as Error & { code?: string };
  return errWithCode.code === "ENOENT" || error.message.includes("spawn fly ENOENT");
}

function dedupeInOrder(values: string[]): string[] {
  return [...new Set(values)];
}
