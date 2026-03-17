import type { ForegroundProcessRunner } from "../../../../adapters/process.js";
import { resolveFlyCommand } from "../../../../adapters/fly-command.js";
import type { RemoteSessionPort } from "../../application/ports/remote-session.port.js";

const REMOTE_HERMES_PATH = "/opt/hermes/hermes-agent/venv/bin/hermes";
const REMOTE_HERMES_HOME = "/root/.hermes";
const REMOTE_BASH_PATH = "/bin/bash";

export class FlyRemoteSession implements RemoteSessionPort {
  constructor(
    private readonly processRunner: ForegroundProcessRunner,
    private readonly env?: NodeJS.ProcessEnv
  ) {}

  async openAgentConsole(appName: string, hermesArgs: string[]): Promise<{ ok: boolean; error?: string }> {
    return this.runForeground(
      ["ssh", "console", "-a", appName, "--pty", "-C", buildRemoteHermesCommand(hermesArgs)],
      `Failed to open Hermes CLI for app '${appName}'.`
    );
  }

  async openShell(appName: string): Promise<{ ok: boolean; error?: string }> {
    return this.runForeground(
      ["ssh", "console", "-a", appName, "--pty", "-C", buildRemoteShellCommand()],
      `Failed to open a shell for app '${appName}'.`
    );
  }

  async execRemoteCommand(appName: string, commandArgs: string[]): Promise<{ ok: boolean; error?: string }> {
    return this.runForeground(
      ["ssh", "console", "-a", appName, "-C", buildRemoteExecCommand(commandArgs)],
      `Failed to execute the remote command for app '${appName}'.`
    );
  }

  async execHermesCommand(appName: string, hermesArgs: string[]): Promise<{ ok: boolean; error?: string }> {
    return this.runForeground(
      ["ssh", "console", "-a", appName, "--pty", "-C", buildRemoteHermesCommand(hermesArgs)],
      `Failed to execute the Hermes command for app '${appName}'.`
    );
  }

  private async runForeground(
    args: string[],
    failureMessage: string
  ): Promise<{ ok: boolean; error?: string }> {
    try {
      const flyCommand = await resolveFlyCommand(this.env);
      const result = await this.processRunner.runForeground(flyCommand, args, { env: this.env });
      if (result.exitCode !== 0) {
        return { ok: false, error: failureMessage };
      }
      return { ok: true };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { ok: false, error: message };
    }
  }
}

function buildRemoteHermesCommand(hermesArgs: string[]): string {
  const renderedArgs = hermesArgs.map(shellEscape).join(" ");
  const launchHermes = renderedArgs.length > 0
    ? `cd ${shellEscape(REMOTE_HERMES_HOME)} && exec ${shellEscape(REMOTE_HERMES_PATH)} ${renderedArgs}`
    : `cd ${shellEscape(REMOTE_HERMES_HOME)} && exec ${shellEscape(REMOTE_HERMES_PATH)}`;
  return buildRemoteBootstrap(launchHermes);
}

function buildRemoteShellCommand(): string {
  const launchShell = `cd ${shellEscape(REMOTE_HERMES_HOME)} && exec ${shellEscape(REMOTE_BASH_PATH)} -il`;
  return buildRemoteBootstrap(launchShell);
}

function buildRemoteExecCommand(commandArgs: string[]): string {
  const renderedArgs = commandArgs.map(shellEscape).join(" ");
  const launch = renderedArgs.length > 0
    ? `cd ${shellEscape(REMOTE_HERMES_HOME)} && exec ${renderedArgs}`
    : `cd ${shellEscape(REMOTE_HERMES_HOME)} && exec ${shellEscape(REMOTE_BASH_PATH)} -lc ${shellEscape("true")}`;
  return buildRemoteBootstrap(launch);
}

function buildRemoteBootstrap(launchCommand: string): string {
  const anthropicBootstrap = [
    "export HOME=/root",
    `if [ -z "\${ANTHROPIC_TOKEN:-}" ] && [ -f ${shellEscape(`${REMOTE_HERMES_HOME}/.anthropic_oauth.json`)} ]; then`,
    `  _anthropic_token="$(python3 -c ${shellEscape(
      "import json; from pathlib import Path; data = json.loads(Path('/root/.hermes/.anthropic_oauth.json').read_text(encoding='utf-8')); token = str(data.get('accessToken', '')).strip(); print(token) if token else None"
    )} 2>/dev/null || true)"`,
    '  if [ -n "$_anthropic_token" ]; then',
    '    export ANTHROPIC_TOKEN="$_anthropic_token"',
    "  fi",
    "fi",
    launchCommand,
  ].join("\n");
  return `sh -lc ${shellEscape(anthropicBootstrap)}`;
}

function shellEscape(value: string): string {
  return `'${value.replaceAll("'", `'\"'\"'`)}'`;
}
