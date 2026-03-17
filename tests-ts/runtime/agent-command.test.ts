import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { runAgentCommand } from "../../src/commands/agent.ts";
import { ExecuteAgentCommandUseCase } from "../../src/contexts/runtime/application/use-cases/execute-agent-command.ts";

function makeIO() {
  const errLines: string[] = [];
  return {
    stderr: { write: (s: string) => { errLines.push(s); } },
    get errText() { return errLines.join(""); }
  };
}

describe("runAgentCommand", () => {
  it("runs a Hermes subcommand against an explicit app", async () => {
    const calls: Array<{ appName: string; hermesArgs: string[] }> = [];
    const useCase = new ExecuteAgentCommandUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async (appName, hermesArgs) => {
        calls.push({ appName, hermesArgs });
        return { ok: true };
      },
    });
    const io = makeIO();

    const code = await runAgentCommand(["-a", "test-app", "model"], {
      useCase,
      env: { HOME: "" },
      ...io,
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "test-app", hermesArgs: ["model"] }]);
  });

  it("uses current_app and treats all args as Hermes subcommands when no explicit app is provided", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-agent-current-"));
    await writeFile(join(root, "config.yaml"), "current_app: current-app\n", "utf8");
    const calls: Array<{ appName: string; hermesArgs: string[] }> = [];
    const useCase = new ExecuteAgentCommandUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async (appName, hermesArgs) => {
        calls.push({ appName, hermesArgs });
        return { ok: true };
      },
    });
    const io = makeIO();

    const code = await runAgentCommand(["gateway", "setup"], {
      useCase,
      env: { HOME: "", HERMES_FLY_CONFIG_DIR: root },
      ...io,
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "current-app", hermesArgs: ["gateway", "setup"] }]);
  });

  it("requires at least one Hermes subcommand", async () => {
    const io = makeIO();

    const code = await runAgentCommand(["-a", "test-app"], {
      env: { HOME: "" },
      ...io,
    });

    assert.equal(code, 1);
    assert.match(io.errText, /No Hermes subcommand specified/);
  });
});
