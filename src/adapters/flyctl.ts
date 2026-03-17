import type { ProcessResult, ProcessRunOptions, ProcessRunner } from "./process.js";
import { resolveFlyCommand } from "./fly-command.js";
import { telegramBotLink } from "../contexts/messaging/infrastructure/adapters/telegram-links.js";

export type AppStatusOk = {
  ok: true;
  appName: string;
  status: string | null;
  hostname: string | null;
  machineState: string | null;
  region: string | null;
};

export type AppStatusError = {
  ok: false;
  error: string;
};

export type AppStatusResult = AppStatusOk | AppStatusError;

export type MachineSummary = {
  id: string | null;
  state: string | null;
  region: string | null;
};

export type TelegramBotIdentity = {
  configured: boolean;
  username: string | null;
  link: string | null;
};

export interface FlyctlPort {
  listLiveAppNames(): Promise<Set<string> | null>;
  getMachineSummary(appName: string): Promise<MachineSummary>;
  getMachineState(appName: string): Promise<string | null>;
  getAiAccessMode(appName: string): Promise<string | null>;
  getTelegramBotIdentity(appName: string): Promise<TelegramBotIdentity>;
  getAppStatus(appName: string): Promise<AppStatusResult>;
  getAppLogs(appName: string): Promise<ProcessResult>;
  streamAppLogs(appName: string, options?: ProcessRunOptions): Promise<{ exitCode: number }>;
}

export class FlyctlAdapter implements FlyctlPort {
  private flyReadyPromise: Promise<boolean> | null = null;

  constructor(
    private readonly processRunner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async listLiveAppNames(): Promise<Set<string> | null> {
    if (!await this.isFlyReady()) {
      return null;
    }

    const flyCommand = await resolveFlyCommand(this.env);
    const stdout = await this.runFlyJson(flyCommand, ["apps", "list", "--json"]);
    if (stdout === null) {
      return null;
    }

    return parseLiveAppNames(stdout);
  }

  async getMachineSummary(appName: string): Promise<MachineSummary> {
    if (!await this.isFlyReady()) {
      return { id: null, state: null, region: null };
    }

    const flyCommand = await resolveFlyCommand(this.env);
    const machineList = await this.runFlyJson(flyCommand, ["machine", "list", "-a", appName, "--json"]);
    const listedMachine = parseMachineList(machineList);
    if (listedMachine !== null) {
      return listedMachine;
    }

    const statusJson = await this.runFlyJson(flyCommand, ["status", "--app", appName, "--json"]);
    const statusMachine = parseStatusMachine(statusJson);
    if (statusMachine !== null) {
      return statusMachine;
    }

    return { id: null, state: null, region: null };
  }

  async getMachineState(appName: string): Promise<string | null> {
    const machine = await this.getMachineSummary(appName);
    return machine.state;
  }

  async getAiAccessMode(appName: string): Promise<string | null> {
    if (!await this.isFlyReady()) {
      return null;
    }

    const secretNames = await this.getSecretNames(appName);
    return inferAiAccessMode(secretNames);
  }

  async getTelegramBotIdentity(appName: string): Promise<TelegramBotIdentity> {
    if (!await this.isFlyReady()) {
      return { configured: false, username: null, link: null };
    }

    const secretNames = await this.getSecretNames(appName);
    const hasTelegramToken = secretNames.includes("TELEGRAM_BOT_TOKEN") || secretNames.includes("BOT_TOKEN");
    if (!hasTelegramToken) {
      return { configured: false, username: null, link: null };
    }

    try {
      const flyCommand = await resolveFlyCommand(this.env);
      const result = await this.processRunner.run(
        flyCommand,
        [
          "ssh",
          "console",
          "-a",
          appName,
          "-C",
          "sh -lc 'token=${TELEGRAM_BOT_TOKEN:-${BOT_TOKEN:-}}; if [ -n \"$token\" ]; then curl -fsSL --max-time 10 \"https://api.telegram.org/bot${token}/getMe\"; fi'"
        ],
        { timeoutMs: 4_000 }
      );
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return { configured: true, username: null, link: null };
      }

      const payload = JSON.parse(result.stdout) as {
        ok?: boolean;
        result?: { username?: unknown };
      };
      const username = String(payload.result?.username ?? "").trim();
      if (payload.ok !== true || username.length === 0) {
        return { configured: true, username: null, link: null };
      }

      return {
        configured: true,
        username,
        link: telegramBotLink(username)
      };
    } catch {
      return { configured: true, username: null, link: null };
    }
  }

  async getAppStatus(appName: string): Promise<AppStatusResult> {
    if (!await this.isFlyReady()) {
      return { ok: false, error: "Fly.io CLI not ready" };
    }

    let result;
    try {
      const flyCommand = await resolveFlyCommand(this.env);
      result = await this.processRunner.run(flyCommand, ["status", "--app", appName, "--json"], { timeoutMs: 4_000 });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return { ok: false, error: msg };
    }

    if (result.exitCode !== 0) {
      const error =
        result.stderr.trim().length > 0
          ? result.stderr.trim()
          : result.stdout.trim().length > 0
            ? result.stdout.trim()
            : "unknown error";
      return { ok: false, error };
    }

    try {
      const parsed = JSON.parse(result.stdout) as {
        app?: {
          name?: unknown;
          status?: unknown;
          hostname?: unknown;
        };
        machines?: Array<Record<string, unknown>>;
        Machines?: Array<Record<string, unknown>>;
      };

      const app = parsed.app ?? {};

      const appName_ =
        typeof app.name === "string" && app.name.length > 0 ? app.name : appName;
      const status =
        typeof app.status === "string" && app.status.length > 0 ? app.status : null;
      const hostname =
        typeof app.hostname === "string" && app.hostname.length > 0 ? app.hostname : null;

      const machines = Array.isArray(parsed.machines)
        ? parsed.machines
        : Array.isArray(parsed.Machines)
          ? parsed.Machines
          : [];

      const first = machines[0] ?? {};
      const machineState =
        typeof first.state === "string" && first.state.length > 0 ? first.state : null;
      const region =
        typeof first.region === "string" && first.region.length > 0 ? first.region : null;

      return {
        ok: true,
        appName: appName_,
        status,
        hostname,
        machineState,
        region
      };
    } catch {
      const error =
        result.stderr.trim().length > 0
          ? result.stderr.trim()
          : result.stdout.trim().length > 0
            ? result.stdout.trim()
            : "unknown error";
      return { ok: false, error };
    }
  }

  async getAppLogs(appName: string): Promise<ProcessResult> {
    if (!await this.isFlyReady()) {
      return { stdout: "", stderr: "Fly.io CLI not ready", exitCode: 1 };
    }

    const flyCommand = await resolveFlyCommand(this.env);
    return this.processRunner.run(flyCommand, ["logs", "--app", appName], { timeoutMs: 8_000 });
  }

  async streamAppLogs(appName: string, options?: ProcessRunOptions): Promise<{ exitCode: number }> {
    if (!await this.isFlyReady()) {
      return { exitCode: 1 };
    }

    const flyCommand = await resolveFlyCommand(this.env);
    return this.processRunner.runStreaming(flyCommand, ["logs", "--app", appName], options);
  }

  private async getSecretNames(appName: string): Promise<string[]> {
    try {
      const flyCommand = await resolveFlyCommand(this.env);
      const result = await this.processRunner.run(
        flyCommand,
        ["secrets", "list", "--app", appName, "--json"],
        { timeoutMs: 3_000 }
      );
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return [];
      }

      const parsed = JSON.parse(result.stdout) as Array<{ Name?: unknown; name?: unknown }>;
      if (!Array.isArray(parsed)) {
        return [];
      }

      return parsed
        .map((entry) => {
          const value = entry.Name ?? entry.name;
          return typeof value === "string" ? value.trim() : "";
        })
        .filter((value) => value.length > 0);
    } catch {
      return [];
    }
  }

  private async runFlyJson(command: string, args: string[]): Promise<string | null> {
    try {
      const result = await this.processRunner.run(command, args, { timeoutMs: 3_000 });
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return null;
      }
      return result.stdout;
    } catch {
      return null;
    }
  }

  private async isFlyReady(): Promise<boolean> {
    if (this.flyReadyPromise === null) {
      this.flyReadyPromise = this.probeFlyReady();
    }

    return await this.flyReadyPromise;
  }

  private async probeFlyReady(): Promise<boolean> {
    try {
      const flyCommand = await resolveFlyCommand(this.env);
      const result = await this.processRunner.run(
        flyCommand,
        ["auth", "whoami", "-j"],
        { timeoutMs: 2_000 }
      );
      return result.exitCode === 0;
    } catch {
      return false;
    }
  }
}

function inferAiAccessMode(secretNames: string[]): string | null {
  if (secretNames.includes("HERMES_ANTHROPIC_OAUTH_JSON_B64")) {
    return "anthropic";
  }
  if (secretNames.includes("HERMES_AUTH_JSON_B64")) {
    return "openai-codex";
  }
  if (secretNames.includes("OPENROUTER_API_KEY")) {
    return "openrouter";
  }
  return null;
}

function parseMachineList(stdout: string | null): MachineSummary | null {
  if (stdout === null) {
    return null;
  }

  try {
    const parsed = JSON.parse(stdout) as Array<Record<string, unknown>>;
    const machines = Array.isArray(parsed) ? parsed : [];
    if (machines.length === 0) {
      return null;
    }

    return normalizeMachineRecord(machines[0] ?? {});
  } catch {
    return null;
  }
}

function parseStatusMachine(stdout: string | null): MachineSummary | null {
  if (stdout === null) {
    return null;
  }

  try {
    const parsed = JSON.parse(stdout) as {
      machines?: Array<Record<string, unknown>>;
      Machines?: Array<Record<string, unknown>>;
    };
    const machines = Array.isArray(parsed.machines)
      ? parsed.machines
      : Array.isArray(parsed.Machines)
        ? parsed.Machines
        : [];

    if (machines.length === 0) {
      return null;
    }

    return normalizeMachineRecord(machines[0] ?? {});
  } catch {
    return null;
  }
}

function normalizeMachineRecord(record: Record<string, unknown>): MachineSummary {
  const idValue = record.id ?? record.ID ?? null;
  const stateValue = record.state ?? record.State ?? null;
  const regionValue = record.region ?? record.Region ?? null;

  return {
    id: typeof idValue === "string" && idValue.length > 0 ? idValue : null,
    state: typeof stateValue === "string" && stateValue.length > 0 ? stateValue : null,
    region: typeof regionValue === "string" && regionValue.length > 0 ? regionValue : null
  };
}

function parseLiveAppNames(stdout: string): Set<string> | null {
  try {
    const parsed = JSON.parse(stdout) as Array<Record<string, unknown>>;
    if (!Array.isArray(parsed)) {
      return null;
    }

    const names = parsed
      .map((entry) => {
        const direct = entry.name ?? entry.Name;
        if (typeof direct === "string" && direct.trim().length > 0) {
          return direct.trim();
        }

        const app = entry.app;
        if (app && typeof app === "object") {
          const nested = (app as Record<string, unknown>).name;
          if (typeof nested === "string" && nested.trim().length > 0) {
            return nested.trim();
          }
        }

        return "";
      })
      .filter((value) => value.length > 0);

    return new Set(names);
  } catch {
    return null;
  }
}
