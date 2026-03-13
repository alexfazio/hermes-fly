import type { ProcessResult, ProcessRunner } from "./process.js";

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

export interface FlyctlPort {
  getMachineState(appName: string): Promise<string | null>;
  getAppStatus(appName: string): Promise<AppStatusResult>;
  getAppLogs(appName: string): Promise<ProcessResult>;
}

export class FlyctlAdapter implements FlyctlPort {
  constructor(private readonly processRunner: ProcessRunner) {}

  async getMachineState(appName: string): Promise<string | null> {
    let result;
    try {
      result = await this.processRunner.run("fly", ["status", "--app", appName, "--json"]);
    } catch {
      return null;
    }

    if (result.exitCode !== 0) {
      return null;
    }

    try {
      const parsed = JSON.parse(result.stdout) as {
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

      const first = machines[0] ?? {};
      const state = first.state;
      if (typeof state === "string" && state.length > 0) {
        return state;
      }

      return null;
    } catch {
      return null;
    }
  }

  async getAppStatus(appName: string): Promise<AppStatusResult> {
    let result;
    try {
      result = await this.processRunner.run("fly", ["status", "--app", appName, "--json"]);
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
    return this.processRunner.run("fly", ["logs", "--app", appName]);
  }
}
