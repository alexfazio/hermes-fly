import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { FlyDestroyRunner } from "../../src/contexts/release/infrastructure/adapters/fly-destroy-runner.ts";

describe("FlyDestroyRunner", () => {
  it("uses TELEGRAM_BOT_TOKEN when logging out Telegram before destroy", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner = new FlyDestroyRunner({
      run: async (command, args) => {
        calls.push({ command, args });
        return { stdout: "", stderr: "", exitCode: 0 };
      }
    });

    await runner.telegramLogout("test-app");

    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.command, "fly");
    assert.deepEqual(calls[0]?.args.slice(0, 5), ["ssh", "console", "-a", "test-app", "-C"]);
    assert.match(calls[0]?.args[5] ?? "", /TELEGRAM_BOT_TOKEN/);
    assert.match(calls[0]?.args[5] ?? "", /logOut/);
  });
});
