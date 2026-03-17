import type { RemoteSessionPort } from "../ports/remote-session.port.js";

export type ExecuteRemoteCommandResult =
  | { kind: "ok" }
  | { kind: "error"; message: string };

export class ExecuteRemoteCommandUseCase {
  constructor(private readonly port: RemoteSessionPort) {}

  async execute(appName: string, commandArgs: string[]): Promise<ExecuteRemoteCommandResult> {
    const result = await this.port.execRemoteCommand(appName, commandArgs);
    if (!result.ok) {
      return { kind: "error", message: result.error ?? "failed to execute remote command" };
    }

    return { kind: "ok" };
  }
}
