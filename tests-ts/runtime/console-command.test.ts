import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { runConsoleCommand } from "../../src/commands/console.ts";
import { OpenConsoleUseCase } from "../../src/contexts/runtime/application/use-cases/open-console.ts";
import type { RemoteSessionPort } from "../../src/contexts/runtime/application/ports/remote-session.port.ts";

function makeIO() {
  const outLines: string[] = [];
  const errLines: string[] = [];
  return {
    stdout: { write: (s: string) => { outLines.push(s); } },
    stderr: { write: (s: string) => { errLines.push(s); } },
    get outText() { return outLines.join(""); },
    get errText() { return errLines.join(""); }
  };
}

describe("runConsoleCommand", () => {
  it("opens the remote Hermes CLI for an explicit app", async () => {
    const calls: Array<{ appName: string; mode: string; hermesArgs: string[] }> = [];
    const useCase = new OpenConsoleUseCase({
      openAgentConsole: async (appName, hermesArgs) => {
        calls.push({ appName, mode: "agent", hermesArgs });
        return { ok: true };
      },
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runConsoleCommand(["-a", "test-app"], {
      useCase,
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "test-app", mode: "agent", hermesArgs: [] }]);
  });

  it("treats the first positional argument as the app name and forwards the rest to Hermes", async () => {
    const calls: Array<{ appName: string; mode: string; hermesArgs: string[] }> = [];
    const useCase = new OpenConsoleUseCase({
      openAgentConsole: async (appName, hermesArgs) => {
        calls.push({ appName, mode: "agent", hermesArgs });
        return { ok: true };
      },
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runConsoleCommand(["test-app", "chat", "-q", "hello"], {
      useCase,
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "test-app", mode: "agent", hermesArgs: ["chat", "-q", "hello"] }]);
  });

  it("opens an interactive shell when -s is selected", async () => {
    const calls: Array<{ appName: string; mode: string }> = [];
    const useCase = new OpenConsoleUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async (appName) => {
        calls.push({ appName, mode: "shell" });
        return { ok: true };
      },
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runConsoleCommand(["-s", "test-app"], {
      useCase,
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "test-app", mode: "shell" }]);
  });

  it("uses current_app for shell mode when -s is selected without an explicit app", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-fly-console-shell-current-"));
    await writeFile(join(root, "config.yaml"), "current_app: current-app\n", "utf8");
    const calls: Array<{ appName: string; mode: string }> = [];
    const useCase = new OpenConsoleUseCase({
      openAgentConsole: async () => ({ ok: true }),
      openShell: async (appName) => {
        calls.push({ appName, mode: "shell" });
        return { ok: true };
      },
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runConsoleCommand(["-s"], {
      useCase,
      env: { HOME: "", HERMES_FLY_CONFIG_DIR: root },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(calls, [{ appName: "current-app", mode: "shell" }]);
  });

  it("rejects mixing -a and -s in the same console invocation", async () => {
    const io = makeIO();

    const code = await runConsoleCommand(["-a", "app-one", "-s", "app-two"], {
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 1);
    assert.match(io.errText, /Choose either -a for agent mode or -s for shell mode/);
  });

  it("returns a friendly error when no app can be resolved", async () => {
    const io = makeIO();

    const code = await runConsoleCommand([], {
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 1);
    assert.match(io.errText, /No app specified/);
  });

  it("returns a friendly error when flyctl is missing", async () => {
    const useCase = new OpenConsoleUseCase({
      openAgentConsole: async () => ({ ok: false, error: "spawn fly ENOENT" }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    });
    const io = makeIO();

    const code = await runConsoleCommand(["-a", "test-app"], {
      useCase,
      env: { HOME: "" },
      ...io
    });

    assert.equal(code, 1);
    assert.match(io.errText, /Fly\.io CLI not found/);
  });
});

describe("OpenConsoleUseCase", () => {
  it("surfaces adapter failures as error results", async () => {
    const port: RemoteSessionPort = {
      openAgentConsole: async () => ({ ok: false, error: "boom" }),
      openShell: async () => ({ ok: true }),
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    };

    const useCase = new OpenConsoleUseCase(port);
    const result = await useCase.execute("test-app", "agent", []);

    assert.deepEqual(result, { kind: "error", message: "boom" });
  });

  it("delegates shell mode to the shell adapter path", async () => {
    const calls: string[] = [];
    const port: RemoteSessionPort = {
      openAgentConsole: async () => ({ ok: true }),
      openShell: async () => {
        calls.push("shell");
        return { ok: true };
      },
      execRemoteCommand: async () => ({ ok: true }),
      execHermesCommand: async () => ({ ok: true }),
    };

    const useCase = new OpenConsoleUseCase(port);
    const result = await useCase.execute("test-app", "shell", []);

    assert.deepEqual(result, { kind: "ok" });
    assert.deepEqual(calls, ["shell"]);
  });
});
