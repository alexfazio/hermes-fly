import type { DestroyRunnerPort } from "../../application/ports/destroy-runner.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";
import { resolveFlyCommand } from "../../../../adapters/fly-command.js";

export class FlyDestroyRunner implements DestroyRunnerPort {
  constructor(
    private readonly processRunner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async destroyApp(appName: string): Promise<{ ok: boolean }> {
    const flyCommand = await this.resolveFlyCommand();
    const result = await this.processRunner.run(
      flyCommand,
      ["apps", "destroy", appName, "--yes"],
      { env: this.env }
    );
    return { ok: result.exitCode === 0 };
  }

  async cleanupVolumes(appName: string): Promise<void> {
    const flyCommand = await this.resolveFlyCommand();
    // List and delete volumes for the app (fail-soft)
    const listResult = await this.processRunner.run(
      flyCommand,
      ["volumes", "list", "-a", appName, "--json"],
      { env: this.env }
    );
    if (listResult.exitCode !== 0) return;

    let volumes: Array<{ id: string }>;
    try {
      volumes = JSON.parse(listResult.stdout);
    } catch {
      return;
    }

    for (const vol of volumes) {
      if (typeof vol.id === "string") {
        await this.processRunner.run(
          flyCommand,
          ["volumes", "delete", vol.id, "--yes"],
          { env: this.env }
        ).catch(() => {});
      }
    }
  }

  async telegramLogout(appName: string): Promise<void> {
    const flyCommand = await this.resolveFlyCommand();
    // Best-effort: SSH into the app and call the Telegram logOut API.
    // Hermes stores the token as TELEGRAM_BOT_TOKEN; BOT_TOKEN is kept as a fallback.
    await this.processRunner.run(
      flyCommand,
      [
        "ssh",
        "console",
        "-a",
        appName,
        "-C",
        "sh -lc 'token=${TELEGRAM_BOT_TOKEN:-${BOT_TOKEN:-}}; if [ -n \"$token\" ]; then curl -fsSL --max-time 10 \"https://api.telegram.org/bot${token}/logOut\" >/dev/null 2>&1 || true; fi'"
      ],
      { env: this.env }
    );
  }

  async removeConfig(appName: string): Promise<void> {
    // Remove the app from the local config file
    const configDir = this.env?.HERMES_FLY_CONFIG_DIR ?? "";
    if (!configDir) return;

    const { readFile, writeFile } = await import("node:fs/promises");
    const { join } = await import("node:path");
    const configPath = join(configDir, "config.yaml");

    let content: string;
    try {
      content = await readFile(configPath, "utf8");
    } catch {
      return;
    }

    // Remove app block from apps list (basic yaml manipulation)
    const lines = content.split("\n");
    const filtered: string[] = [];
    let skipBlock = false;
    for (const line of lines) {
      if (line.match(/^\s+-\s+name:\s*/) && line.includes(appName)) {
        skipBlock = true;
        continue;
      }
      if (skipBlock && line.match(/^\s+-\s+name:\s*/)) {
        skipBlock = false;
      }
      if (!skipBlock) {
        filtered.push(line);
      }
    }

    await writeFile(configPath, filtered.join("\n"), "utf8");
  }

  private async resolveFlyCommand(): Promise<string> {
    return resolveFlyCommand(this.env);
  }
}
