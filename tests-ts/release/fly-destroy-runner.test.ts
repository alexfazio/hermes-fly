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

  it("classifies missing apps as not_found and other destroy failures as failed", async () => {
    const runner = new FlyDestroyRunner({
      run: async (_command, args) => {
        if (args[0] === "apps" && args[1] === "destroy" && args[2] === "missing-app") {
          return { stdout: "", stderr: "Could not find App", exitCode: 1 };
        }
        return { stdout: "", stderr: "permission denied", exitCode: 1 };
      }
    });

    const missing = await runner.destroyApp("missing-app");
    const failed = await runner.destroyApp("broken-app");

    assert.deepEqual(missing, { ok: false, reason: "not_found", error: "Could not find App" });
    assert.deepEqual(failed, { ok: false, reason: "failed", error: "permission denied" });
  });

  it("removes the target app from the default HOME-based config and clears matching current_app", async () => {
    const root = await mkdtemp(join(tmpdir(), "fly-destroy-runner-config-"));
    const configDir = join(root, ".hermes-fly");
    const configPath = join(configDir, "config.yaml");

    try {
      await mkdir(configDir, { recursive: true });
      await writeFile(
        configPath,
        [
          "current_app: stale-app",
          "apps:",
          "  - name: stale-app",
          "    region: fra",
          "  - name: live-app",
          "    region: ams",
          "metadata: keep-me",
          ""
        ].join("\n"),
        "utf8"
      );

      const runner = new FlyDestroyRunner(
        {
          run: async () => ({ stdout: "", stderr: "", exitCode: 0 })
        },
        { HOME: root }
      );

      await runner.removeConfig("stale-app");

      const updated = await import("node:fs/promises").then(({ readFile }) => readFile(configPath, "utf8"));
      assert.doesNotMatch(updated, /current_app: stale-app/);
      assert.doesNotMatch(updated, /- name: stale-app/);
      assert.match(updated, /- name: live-app/);
      assert.match(updated, /metadata: keep-me/);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
