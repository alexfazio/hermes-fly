import { NodeProcessRunner, type ProcessRunner } from "../../../../adapters/process.js";

export interface BrowserOpenerPort {
  open(url: string): Promise<{ ok: boolean; error?: string }>;
}

export class SystemBrowserOpener implements BrowserOpenerPort {
  constructor(
    private readonly processRunner: ProcessRunner = new NodeProcessRunner(),
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async open(url: string): Promise<{ ok: boolean; error?: string }> {
    const platform = (this.env?.HERMES_FLY_PLATFORM ?? process.platform).trim();
    const attempts: Array<[string, string[]]> = platform === "darwin"
      ? [["open", [url]]]
      : platform === "linux"
        ? [["xdg-open", [url]]]
        : platform === "win32"
          ? [["cmd", ["/c", "start", "", url]]]
          : [];

    if (attempts.length === 0) {
      return { ok: false, error: `Unsupported platform for browser opening: ${platform}` };
    }

    for (const [command, args] of attempts) {
      try {
        const result = await this.processRunner.run(command, args, {
          env: this.env,
          timeoutMs: 5_000,
        });
        if (result.exitCode === 0) {
          return { ok: true };
        }
        return { ok: false, error: result.stderr || result.stdout || "browser open failed" };
      } catch (error) {
        return { ok: false, error: error instanceof Error ? error.message : String(error) };
      }
    }

    return { ok: false, error: "browser open failed" };
  }
}
