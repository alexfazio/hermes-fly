import type { RemoteSessionPort } from "../ports/remote-session.port.js";

export type ExecuteAgentCommandResult =
  | { kind: "ok" }
  | { kind: "error"; message: string };

export class ExecuteAgentCommandUseCase {
  constructor(private readonly port: RemoteSessionPort) {}

  async execute(appName: string, hermesArgs: string[]): Promise<ExecuteAgentCommandResult> {
    const result = await this.port.execHermesCommand(appName, hermesArgs);
    if (!result.ok) {
      return { kind: "error", message: result.error ?? "failed to execute Hermes command" };
    }

    return { kind: "ok" };
  }
}
