import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { FlyRemoteSession } from "../../src/contexts/runtime/infrastructure/adapters/fly-remote-session.ts";
import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";

describe("FlyRemoteSession", () => {
  it("opens Hermes over fly ssh console in the deployed app", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      runStreaming: async () => ({ exitCode: 0 }),
      runForeground: async (command, args) => {
        calls.push({ command, args });
        return { exitCode: 0 };
      }
    };

    const adapter = new FlyRemoteSession(runner, { HOME: "", PATH: "" });
    const result = await adapter.openAgentConsole("test-app", ["chat", "-q", "hello world"]);

    assert.deepEqual(result, { ok: true });
    assert.equal(calls[0]?.command, "fly");
    assert.deepEqual(calls[0]?.args.slice(0, 4), ["ssh", "console", "-a", "test-app"]);
    assert.equal(calls[0]?.args[4], "--pty");
    assert.equal(calls[0]?.args[5], "-C");
    assert.match(calls[0]?.args[6] ?? "", /\/opt\/hermes\/hermes-agent\/venv\/bin\/hermes/);
    assert.match(calls[0]?.args[6] ?? "", /chat/);
    assert.match(calls[0]?.args[6] ?? "", /hello world/);
  });

  it("opens a PTY shell in /root/.hermes", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      runStreaming: async () => ({ exitCode: 0 }),
      runForeground: async (command, args) => {
        calls.push({ command, args });
        return { exitCode: 0 };
      }
    };

    const adapter = new FlyRemoteSession(runner, { HOME: "", PATH: "" });
    const result = await adapter.openShell("test-app");

    assert.deepEqual(result, { ok: true });
    assert.equal(calls[0]?.args[4], "--pty");
    assert.equal(calls[0]?.args[5], "-C");
    assert.match(calls[0]?.args[6] ?? "", /\/root\/\.hermes/);
    assert.match(calls[0]?.args[6] ?? "", /\/bin\/bash/);
    assert.match(calls[0]?.args[6] ?? "", /-il/);
  });

  it("executes a raw remote command without forcing Hermes", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      runStreaming: async () => ({ exitCode: 0 }),
      runForeground: async (command, args) => {
        calls.push({ command, args });
        return { exitCode: 0 };
      }
    };

    const adapter = new FlyRemoteSession(runner, { HOME: "", PATH: "" });
    const result = await adapter.execRemoteCommand("test-app", ["ls", "-la"]);

    assert.deepEqual(result, { ok: true });
    assert.deepEqual(calls[0]?.args.slice(0, 5), ["ssh", "console", "-a", "test-app", "-C"]);
    assert.match(calls[0]?.args[5] ?? "", /\/root\/\.hermes/);
    assert.match(calls[0]?.args[5] ?? "", /'ls'/);
    assert.match(calls[0]?.args[5] ?? "", /'-la'/);
  });

  it("bridges Anthropic OAuth access tokens into Hermes command sessions for older startup guards", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      runStreaming: async () => ({ exitCode: 0 }),
      runForeground: async (command, args) => {
        calls.push({ command, args });
        return { exitCode: 0 };
      }
    };

    const adapter = new FlyRemoteSession(runner, { HOME: "", PATH: "" });
    const result = await adapter.execHermesCommand("test-app", ["model"]);

    assert.deepEqual(result, { ok: true });
    assert.equal(calls[0]?.args[4], "--pty");
    assert.equal(calls[0]?.args[5], "-C");
    assert.match(calls[0]?.args[6] ?? "", /ANTHROPIC_TOKEN/);
    assert.match(calls[0]?.args[6] ?? "", /\.anthropic_oauth\.json/);
    assert.match(calls[0]?.args[6] ?? "", /python3 -c/);
    assert.match(calls[0]?.args[6] ?? "", /\/opt\/hermes\/hermes-agent\/venv\/bin\/hermes/);
    assert.match(calls[0]?.args[6] ?? "", /model/);
  });

  it("prefers fly from PATH over a stale ~/.fly/bin/fly shim", async () => {
    const root = await mkdtemp(join(tmpdir(), "fly-remote-session-home-"));
    const pathDir = await mkdtemp(join(tmpdir(), "fly-remote-session-path-"));
    const homeFlyDir = join(root, ".fly", "bin");
    const homeFlyPath = join(homeFlyDir, "fly");
    const pathFlyPath = join(pathDir, "fly");
    const calls: Array<{ command: string; args: string[] }> = [];

    try {
      await mkdir(homeFlyDir, { recursive: true });
      await writeFile(homeFlyPath, "#!/bin/sh\necho mock flyctl\n", "utf8");
      await chmod(homeFlyPath, 0o755);

      await writeFile(pathFlyPath, "#!/bin/sh\nexit 0\n", "utf8");
      await chmod(pathFlyPath, 0o755);

      const runner: ForegroundProcessRunner = {
        run: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
        runStreaming: async () => ({ exitCode: 0 }),
        runForeground: async (command, args) => {
          calls.push({ command, args });
          return { exitCode: 0 };
        }
      };

      const adapter = new FlyRemoteSession(runner, { HOME: root, PATH: pathDir });
      const result = await adapter.openAgentConsole("test-app", []);

      assert.deepEqual(result, { ok: true });
      assert.equal(calls[0]?.command, pathFlyPath);
      assert.notEqual(calls[0]?.command, homeFlyPath);
    } finally {
      await rm(root, { recursive: true, force: true });
      await rm(pathDir, { recursive: true, force: true });
    }
  });
});
