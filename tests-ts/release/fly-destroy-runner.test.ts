import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

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
    assert.match(calls[0]?.command ?? "", /fly$/);
    assert.deepEqual(calls[0]?.args.slice(0, 5), ["ssh", "console", "-a", "test-app", "-C"]);
    assert.match(calls[0]?.args[5] ?? "", /TELEGRAM_BOT_TOKEN/);
    assert.match(calls[0]?.args[5] ?? "", /logOut/);
  });

  it("uses the installed ~/.fly/bin/fly binary when it exists", async () => {
    const root = await mkdtemp(join(tmpdir(), "fly-destroy-runner-home-"));
    const flyBinDir = join(root, ".fly", "bin");
    const flyPath = join(flyBinDir, "fly");
    const calls: Array<{ command: string; args: string[] }> = [];

    try {
      await mkdir(flyBinDir, { recursive: true });
      await writeFile(flyPath, "#!/bin/sh\nexit 0\n", "utf8");
      await chmod(flyPath, 0o755);

      const runner = new FlyDestroyRunner(
        {
          run: async (command, args) => {
            calls.push({ command, args });
            if (args[0] === "volumes" && args[1] === "list") {
              return { stdout: "[]", stderr: "", exitCode: 0 };
            }
            return { stdout: "", stderr: "", exitCode: 0 };
          }
        },
        { HOME: root }
      );

      await runner.destroyApp("test-app");
      await runner.cleanupVolumes("test-app");
      await runner.telegramLogout("test-app");

      assert.equal(calls.length, 3);
      assert.equal(calls[0]?.command, flyPath);
      assert.equal(calls[1]?.command, flyPath);
      assert.equal(calls[2]?.command, flyPath);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
