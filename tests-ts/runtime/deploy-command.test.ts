import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { runDeployCommand } from "../../src/commands/deploy.ts";
import type { DeployWizardPort, DeployConfig } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";

const DEFAULT_CONFIG: DeployConfig = {
  orgSlug: "personal",
  appName: "test-app",
  region: "iad",
  vmSize: "shared-cpu-1x",
  volumeSize: 5,
  provider: "openrouter",
  apiKey: "sk-test",
  model: "anthropic/claude-sonnet-4-20250514",
  channel: "stable",
  hermesRef: "8eefbef91cd715cfe410bba8c13cfab4eb3040df",
  botToken: ""
};

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

function makeWizardPort(overrides: Partial<DeployWizardPort> = {}): DeployWizardPort {
  return {
    checkPlatform: async () => ({ ok: true }),
    checkPrerequisites: async () => ({ ok: true }),
    checkAuth: async () => ({ ok: true }),
    checkConnectivity: async () => ({ ok: true }),
    collectConfig: async () => DEFAULT_CONFIG,
    createBuildContext: async () => ({ buildDir: "/tmp/test-build" }),
    provisionResources: async () => ({ ok: true }),
    runDeploy: async () => ({ ok: true }),
    postDeployCheck: async () => ({ ok: true }),
    saveApp: async () => {},
    ...overrides
  };
}

describe("runDeployCommand - successful deploy", () => {
  it("returns 0 on successful deploy", async () => {
    const io = makeIO();
    const code = await runDeployCommand([], {
      wizard: makeWizardPort(),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(code, 0);
  });

  it("prints a deploy completion summary on success", async () => {
    const io = makeIO();

    const code = await runDeployCommand([], {
      wizard: makeWizardPort(),
      stdout: io.stdout,
      stderr: io.stderr
    });

    assert.equal(code, 0);
    assert.match(io.outText, /Deployment complete/);
    assert.match(io.outText, /Fly organization:\s+personal/);
    assert.match(io.outText, /Deployment name:\s+test-app/);
    assert.match(io.outText, /Location:\s+iad/);
    assert.match(io.outText, /hermes-fly status -a test-app/);
  });

  it("prints the configured Telegram chat link when a bot is set up", async () => {
    const io = makeIO();

    const code = await runDeployCommand([], {
      wizard: makeWizardPort({
        collectConfig: async () => ({
          ...DEFAULT_CONFIG,
          botToken: "123:abc",
          telegramBotUsername: "testhermesbot",
          telegramBotName: "Test Hermes Bot",
          telegramAllowedUsers: "1467489858"
        })
      }),
      stdout: io.stdout,
      stderr: io.stderr
    });

    assert.equal(code, 0);
    assert.match(io.outText, /Telegram:\s+@testhermesbot/);
    assert.match(io.outText, /Chat link:\s+https:\/\/t\.me\/testhermesbot\?start=test-app/);
  });
});

describe("runDeployCommand - channel flag", () => {
  it("accepts --channel flag without error", async () => {
    const io = makeIO();
    const code = await runDeployCommand(["--channel", "preview"], {
      wizard: makeWizardPort(),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(code, 0);
  });

  it("normalizes invalid channel to stable", async () => {
    const captured: string[] = [];
    const io = makeIO();
    await runDeployCommand(["--channel", "badvalue"], {
      wizard: makeWizardPort({
        collectConfig: async (opts) => {
          captured.push(opts.channel);
          return { ...DEFAULT_CONFIG, channel: opts.channel };
        }
      }),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(captured[0], "stable");
  });
});

describe("runDeployCommand - no-auto-install flag", () => {
  it("accepts --no-auto-install flag without crashing", async () => {
    const io = makeIO();
    const code = await runDeployCommand(["--no-auto-install"], {
      wizard: makeWizardPort(),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(code, 0);
  });

  it("passes autoInstall=false when --no-auto-install is set", async () => {
    const captured: Array<{ autoInstall: boolean }> = [];
    const io = makeIO();
    await runDeployCommand(["--no-auto-install"], {
      wizard: makeWizardPort({
        checkPrerequisites: async (opts) => {
          captured.push(opts);
          return { ok: true };
        }
      }),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(captured[0]?.autoInstall, false);
  });
});

describe("runDeployCommand - config collection failure", () => {
  it("returns 1 when config collection fails", async () => {
    const io = makeIO();
    const code = await runDeployCommand([], {
      wizard: makeWizardPort({
        collectConfig: async () => {
          throw new Error("OPENROUTER_API_KEY is required in non-interactive mode");
        }
      }),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(code, 1);
  });
});

describe("runDeployCommand - wizard failure", () => {
  it("returns 1 when wizard fails", async () => {
    const io = makeIO();
    const code = await runDeployCommand([], {
      wizard: makeWizardPort({
        checkPlatform: async () => ({ ok: false, error: "unsupported platform" })
      }),
      stdout: io.stdout,
      stderr: io.stderr
    });
    assert.equal(code, 1);
  });
});
