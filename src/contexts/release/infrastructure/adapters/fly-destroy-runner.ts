import type { DestroyAppResult, DestroyRunnerPort } from "../../application/ports/destroy-runner.port.js";
import type { ProcessRunner } from "../../../../adapters/process.js";
import { resolveFlyCommand } from "../../../../adapters/fly-command.js";
import { resolveConfigDir } from "../../../runtime/infrastructure/adapters/fly-deployment-registry.js";

export class FlyDestroyRunner implements DestroyRunnerPort {
  constructor(
    private readonly processRunner: ProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async destroyApp(appName: string): Promise<DestroyAppResult> {
    const flyCommand = await this.resolveFlyCommand();
    const result = await this.processRunner.run(
      flyCommand,
      ["apps", "destroy", appName, "--yes"],
      { env: this.env }
    );
    if (result.exitCode === 0) {
      return { ok: true };
    }

    const detail = `${result.stderr}\n${result.stdout}`.trim();
    if (/not found/i.test(detail) || /could not find app/i.test(detail)) {
      return { ok: false, reason: "not_found", error: detail };
    }

    return {
      ok: false,
      reason: "failed",
      error: detail.length > 0 ? detail : "unknown error"
    };
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
    const { readFile, writeFile } = await import("node:fs/promises");
    const { join } = await import("node:path");
    const configDir = resolveConfigDir(this.env ?? process.env);
    const configPath = join(configDir, "config.yaml");

    let content: string;
    try {
      content = await readFile(configPath, "utf8");
    } catch {
      return;
    }

    await writeFile(configPath, removeAppFromConfig(content, appName), "utf8");
  }

  private async resolveFlyCommand(): Promise<string> {
    return resolveFlyCommand(this.env);
  }
}

function removeAppFromConfig(content: string, appName: string): string {
  const lines = content.split(/\r?\n/);
  const filtered: string[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index] ?? "";

    const currentAppMatch = line.match(/^current_app:\s*(.*)\s*$/);
    if (currentAppMatch) {
      const currentApp = currentAppMatch[1].trim();
      if (currentApp === appName) {
        index += 1;
        continue;
      }
      filtered.push(line);
      index += 1;
      continue;
    }

    if (line === "apps:") {
      filtered.push(line);
      index += 1;

      while (index < lines.length) {
        const appLine = lines[index] ?? "";
        if (appLine.trim().length === 0) {
          filtered.push(appLine);
          index += 1;
          continue;
        }
        if (/^\S/.test(appLine)) {
          break;
        }

        const appMatch = appLine.match(/^  - name:\s*(.+?)\s*$/);
        if (!appMatch) {
          filtered.push(appLine);
          index += 1;
          continue;
        }

        const blockLines = [appLine];
        const blockName = appMatch[1].trim();
        index += 1;
        while (index < lines.length) {
          const blockLine = lines[index] ?? "";
          if (/^  - name:\s*/.test(blockLine) || /^\S/.test(blockLine)) {
            break;
          }
          blockLines.push(blockLine);
          index += 1;
        }

        if (blockName !== appName) {
          filtered.push(...blockLines);
        }
      }

      continue;
    }

    filtered.push(line);
    index += 1;
  }

  return filtered.join("\n");
}
