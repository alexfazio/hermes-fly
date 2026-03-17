import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { runExecCommand } from "../../src/commands/exec.ts";
import { ExecuteRemoteCommandUseCase } from "../../src/contexts/runtime/application/use-cases/execute-remote-command.ts";

function makeIO() {
  const errLines: string[] = [];
  return {
    stderr: { write: (s: string) => { errLines.push(s); } },
    get errText() { return errLines.join(""); }
  };
}

describe("runExecCommand", () => {
  it("runs a raw command against an explicit app and strips the -- separator", async () => {
    const calls: Array<{ appName: string; commandArgs: string[] }> = [];
    const useCase = new ExecuteRemoteCommandUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async (appName, commandArgs) => {
        calls.push({ appName, commandArgs });
        return { ok: true };
      },
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runExecCommand(["-a", "test-app", "--", "ls", "-la"], {
      useCase,
      env: { HOME: "" },
      ...io,
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "test-app", commandArgs: ["ls", "-la"] }]);
  });

  it("uses current_app and treats all args as the remote command when no explicit app is provided", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-exec-current-"));
    await writeFile(join(root, "config.yaml"), "current_app: current-app\n", "utf8");
    const calls: Array<{ appName: string; commandArgs: string[] }> = [];
    const useCase = new ExecuteRemoteCommandUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async (appName, commandArgs) => {
        calls.push({ appName, commandArgs });
        return { ok: true };
      },
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runExecCommand(["pwd"], {
      useCase,
      env: { HOME: "", HERMES_FLY_CONFIG_DIR: root },
      ...io,
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "current-app", commandArgs: ["pwd"] }]);
  });

  it("requires a remote command to execute", async () => {
    const io = makeIO();

    const code = await runExecCommand(["-a", "test-app"], {
      env: { HOME: "" },
      ...io,
    });

    assert.equal(code, 1);
    assert.match(io.errText, /No remote command specified/);
  });
});
