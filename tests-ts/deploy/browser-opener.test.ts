import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SystemBrowserOpener } from "../../src/contexts/deploy/infrastructure/adapters/browser-opener.ts";
import type { ProcessRunner } from "../../src/adapters/process.ts";

describe("SystemBrowserOpener", () => {
  it("uses macOS open when running on darwin", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ProcessRunner = {
      run: async (command, args) => {
        calls.push({ command, args });
        return { stdout: "", stderr: "", exitCode: 0 };
      },
      runStreaming: async () => ({ exitCode: 0 }),
    };
    const opener = new SystemBrowserOpener(runner, { HERMES_FLY_PLATFORM: "darwin" });

    const result = await opener.open("https://discord.com/developers/applications");

    assert.deepEqual(result, { ok: true });
    assert.deepEqual(calls, [
      { command: "open", args: ["https://discord.com/developers/applications"] },
    ]);
  });

  it("uses xdg-open when running on linux", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner: ProcessRunner = {
      run: async (command, args) => {
        calls.push({ command, args });
        return { stdout: "", stderr: "", exitCode: 0 };
      },
      runStreaming: async () => ({ exitCode: 0 }),
    };
    const opener = new SystemBrowserOpener(runner, { HERMES_FLY_PLATFORM: "linux" });

    const result = await opener.open("https://discord.com/developers/applications");

    assert.deepEqual(result, { ok: true });
    assert.deepEqual(calls, [
      { command: "xdg-open", args: ["https://discord.com/developers/applications"] },
    ]);
  });
});

