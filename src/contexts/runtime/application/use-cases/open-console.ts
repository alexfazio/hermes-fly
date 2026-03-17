import type { RemoteSessionPort } from "../ports/remote-session.port.js";

export type OpenConsoleResult =
  | { kind: "ok" }
  | { kind: "error"; message: string };

export class OpenConsoleUseCase {
  constructor(private readonly port: RemoteSessionPort) {}

  async execute(appName: string, mode: "agent" | "shell", hermesArgs: string[]): Promise<OpenConsoleResult> {
    const result = mode === "shell"
      ? await this.port.openShell(appName)
      : await this.port.openAgentConsole(appName, hermesArgs);
    if (!result.ok) {
      return { kind: "error", message: result.error ?? `failed to open ${mode} console` };
    }

    return { kind: "ok" };
  }
}
