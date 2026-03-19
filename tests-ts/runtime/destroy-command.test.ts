import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { runDestroyCommand } from "../../src/commands/destroy.ts";
import type { DestroyRunnerPort } from "../../src/contexts/release/application/ports/destroy-runner.port.ts";
import type { FlyctlPort } from "../../src/adapters/flyctl.ts";

function makeRunner(overrides: Partial<DestroyRunnerPort> = {}): DestroyRunnerPort {
  return {
    destroyApp: async () => ({ ok: true }),
    cleanupVolumes: async () => {},
    telegramLogout: async () => {},
    removeConfig: async () => {},
    ...overrides
  };
}

function makeFlyctl(
  overrides: Partial<Pick<FlyctlPort, "getTelegramBotIdentity" | "getMachineSummary">> = {}
): Pick<FlyctlPort, "getTelegramBotIdentity" | "getMachineSummary"> {
  return {
    getTelegramBotIdentity: async () => ({ configured: false, username: null, link: null }),
    getMachineSummary: async () => ({ id: null, state: null, region: null }),
    ...overrides
  };
}

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

describe("runDestroyCommand - --force flag", () => {
  it("--force with -a APP skips confirmation and returns 0 on success", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app", "--force"], { runner, ...io });
    assert.equal(code, 0);
  });

  it("--force with app name returns 0 on success", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["--force"], {
      runner,
      appName: "test-app",
      ...io
    });
    assert.equal(code, 0);
  });

  it("bare positional app name is treated as the destroy target", async () => {
    const destroyed: string[] = [];
    const io = makeIO();
    const code = await runDestroyCommand(["explicit-app", "--force"], {
      runner: makeRunner({
        destroyApp: async (appName) => {
          destroyed.push(appName);
          return { ok: true };
        }
      }),
      env: {
        HOME: "",
        HERMES_FLY_CONFIG_DIR: ""
      },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(destroyed, ["explicit-app"]);
  });

  it("multiple positional app names are destroyed sequentially", async () => {
    const destroyed: string[] = [];
    const io = makeIO();
    const code = await runDestroyCommand(["app-one", "app-two", "app-three", "--force"], {
      runner: makeRunner({
        destroyApp: async (appName) => {
          destroyed.push(appName);
          return { ok: true };
        }
      }),
      env: {
        HOME: "",
        HERMES_FLY_CONFIG_DIR: ""
      },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(destroyed, ["app-one", "app-two", "app-three"]);
  });
});

describe("runDestroyCommand - confirmation flow", () => {
  it("confirmation 'yes' proceeds and returns 0", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "yes",
      ...io
    });
    assert.equal(code, 0);
  });

  it("confirmation 'no' aborts and returns 1", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "no",
      ...io
    });
    assert.equal(code, 1);
    const combined = io.outText + io.errText;
    assert.ok(combined.toLowerCase().includes("abort"), `Expected 'abort' in output: ${combined}`);
  });

  it("empty confirmation aborts and returns 1", async () => {
    const runner = makeRunner();
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner,
      confirmationInput: "",
      ...io
    });
    assert.equal(code, 1);
  });

  it("pauses stdin after reading confirmation so the process can exit cleanly", async () => {
    let paused = false;
    let resumed = false;
    let listener: ((chunk: string) => void) | null = null;
    const stdin = {
      setEncoding: (_encoding: BufferEncoding) => {},
      once: (_event: "data", handler: (chunk: string) => void) => {
        listener = handler;
      },
      resume: () => {
        resumed = true;
        listener?.("yes\n");
      },
      pause: () => {
        paused = true;
      }
    };

    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app"], {
      runner: makeRunner(),
      stdin,
      ...io
    });

    assert.equal(code, 0);
    assert.equal(resumed, true);
    assert.equal(paused, true);
  });

  it("prompts once when destroying multiple apps interactively", async () => {
    const destroyed: string[] = [];
    const io = makeIO();
    const code = await runDestroyCommand(["app-one", "app-two"], {
      runner: makeRunner({
        destroyApp: async (appName) => {
          destroyed.push(appName);
          return { ok: true };
        }
      }),
      confirmationInput: "yes",
      env: {
        HOME: "",
        HERMES_FLY_CONFIG_DIR: ""
      },
      ...io
    });

    assert.equal(code, 0);
    assert.deepEqual(destroyed, ["app-one", "app-two"]);
    assert.match(io.outText, /destroy 2 apps \(app-one, app-two\)/);
  });
});

describe("runDestroyCommand - Telegram cleanup guidance", () => {
  it("prints BotFather delete guidance after destroying a Telegram deployment", async () => {
    const dir = await mkdtemp(join(tmpdir(), "destroy-command-config-"));

    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: test-app",
          "apps:",
          "  - name: test-app",
          "    region: fra",
          "    platform: telegram",
          "    telegram_bot_username: testhermesbot",
          ""
        ].join("\n"),
        "utf8"
      );

      const io = makeIO();
      const code = await runDestroyCommand(["-a", "test-app"], {
        runner: makeRunner(),
        flyctl: makeFlyctl(),
        confirmationInput: "yes",
        env: {
          ...process.env,
          HERMES_FLY_CONFIG_DIR: dir
        },
        ...io
      });

      const combined = io.outText + io.errText;
      assert.equal(code, 0);
      assert.match(combined, /Telegram bot cleanup/);
      assert.match(combined, /@testhermesbot/);
      assert.match(combined, /https:\/\/t\.me\/testhermesbot/);
      assert.match(combined, /https:\/\/t\.me\/BotFather\?text=%2Fdeletebot/);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("uses live Fly bot identity when saved config lacks the username", async () => {
    const dir = await mkdtemp(join(tmpdir(), "destroy-command-config-live-"));

    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: test-app",
          "apps:",
          "  - name: test-app",
          "    region: fra",
          "    platform: telegram",
          ""
        ].join("\n"),
        "utf8"
      );

      const io = makeIO();
      const code = await runDestroyCommand(["-a", "test-app", "--force"], {
        runner: makeRunner(),
        flyctl: makeFlyctl({
          getTelegramBotIdentity: async () => ({
            configured: true,
            username: "livebot",
            link: "https://t.me/livebot"
          })
        }),
        env: {
          ...process.env,
          HERMES_FLY_CONFIG_DIR: dir
        },
        ...io
      });

      assert.equal(code, 0);
      assert.match(io.outText, /@livebot/);
      assert.match(io.outText, /https:\/\/t\.me\/livebot/);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("resolves machine ids to app names and does not show Telegram cleanup for non-Telegram deployments", async () => {
    const dir = await mkdtemp(join(tmpdir(), "destroy-command-machine-id-"));

    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: wa-app",
          "apps:",
          "  - name: wa-app",
          "    region: ams",
          "    platform: whatsapp",
          "  - name: tg-app",
          "    region: fra",
          "    platform: telegram",
          "    telegram_bot_username: testhermesbot",
          ""
        ].join("\n"),
        "utf8"
      );

      const destroyed: string[] = [];
      const io = makeIO();
      const code = await runDestroyCommand(["wa-machine", "--force"], {
        runner: makeRunner({
          destroyApp: async (appName) => {
            destroyed.push(appName);
            return { ok: true };
          }
        }),
        flyctl: makeFlyctl({
          getMachineSummary: async (appName) => {
            if (appName === "wa-app") {
              return { id: "wa-machine", state: "started", region: "ams" };
            }
            if (appName === "tg-app") {
              return { id: "tg-machine", state: "started", region: "fra" };
            }
            return { id: null, state: null, region: null };
          }
        }),
        env: {
          ...process.env,
          HERMES_FLY_CONFIG_DIR: dir
        },
        ...io
      });

      assert.equal(code, 0);
      assert.deepEqual(destroyed, ["wa-app"]);
      assert.doesNotMatch(io.outText + io.errText, /Telegram bot cleanup/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("prompts and cleans up Telegram bots using resolved app names instead of raw machine ids", async () => {
    const dir = await mkdtemp(join(tmpdir(), "destroy-command-machine-batch-"));

    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: tg-app",
          "apps:",
          "  - name: wa-app",
          "    region: ams",
          "    platform: whatsapp",
          "  - name: tg-app",
          "    region: fra",
          "    platform: telegram",
          "    telegram_bot_username: testhermesbot",
          ""
        ].join("\n"),
        "utf8"
      );

      const destroyed: string[] = [];
      const io = makeIO();
      const code = await runDestroyCommand(["wa-machine", "tg-machine"], {
        runner: makeRunner({
          destroyApp: async (appName) => {
            destroyed.push(appName);
            return { ok: true };
          }
        }),
        flyctl: makeFlyctl({
          getMachineSummary: async (appName) => {
            if (appName === "wa-app") {
              return { id: "wa-machine", state: "started", region: "ams" };
            }
            if (appName === "tg-app") {
              return { id: "tg-machine", state: "started", region: "fra" };
            }
            return { id: null, state: null, region: null };
          }
        }),
        confirmationInput: "yes",
        env: {
          ...process.env,
          HERMES_FLY_CONFIG_DIR: dir
        },
        ...io
      });

      assert.equal(code, 0);
      assert.deepEqual(destroyed, ["wa-app", "tg-app"]);
      assert.match(io.outText, /destroy 2 apps \(wa-app, tg-app\)/i);
      assert.match(io.outText, /Telegram bot cleanup for tg-app/i);
      assert.doesNotMatch(io.outText, /Telegram bot cleanup for wa-machine/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe("runDestroyCommand - already absent app cleanup", () => {
  it("returns 0 when app is already absent on Fly and local cleanup succeeds", async () => {
    const runner = makeRunner({ destroyApp: async () => ({ ok: false, reason: "not_found" }) });
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "ghost-app", "--force"], { runner, ...io });
    assert.equal(code, 0);
    assert.ok(io.errText.includes("already absent"), `Expected cleanup success in stderr: ${io.errText}`);
  });
});

describe("runDestroyCommand - no app specified", () => {
  it("returns 1 with error message when no app and no config", async () => {
    const dir = await mkdtemp(join(tmpdir(), "destroy-command-empty-config-"));
    const runner = makeRunner();
    const io = makeIO();
    try {
      const code = await runDestroyCommand([], {
        runner,
        availableApps: [],
        env: {
          HOME: "",
          HERMES_FLY_CONFIG_DIR: dir
        },
        ...io
      });
      assert.equal(code, 1);
      assert.match(io.errText, /No app specified/);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

describe("runDestroyCommand - missing flyctl", () => {
  it("returns a friendly error when flyctl is missing", async () => {
    const error = Object.assign(new Error("spawn fly ENOENT"), { code: "ENOENT" });
    const io = makeIO();
    const code = await runDestroyCommand(["-a", "test-app", "--force"], {
      runner: makeRunner({
        destroyApp: async () => {
          throw error;
        }
      }),
      flyctl: makeFlyctl(),
      ...io
    });

    assert.equal(code, 1);
    assert.match(io.errText, /Fly\.io CLI not found/);
  });
});
