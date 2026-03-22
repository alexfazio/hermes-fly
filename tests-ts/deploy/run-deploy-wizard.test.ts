import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PassThrough, Writable } from "node:stream";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { RunDeployWizardUseCase } from "../../src/contexts/deploy/application/use-cases/run-deploy-wizard.ts";
import type { DeployConfig, DeployWizardPort } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";
import type { PostDeployCleanupPort } from "../../src/contexts/deploy/application/ports/post-deploy-cleanup.port.ts";
import { ReadlineDeployPrompts } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";
import { FlyDeployWizard } from "../../src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts";
import type { DeployPromptPort } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";
import type { QrCodeRendererPort } from "../../src/contexts/deploy/infrastructure/adapters/qr-code.ts";
import type { BrowserOpenerPort } from "../../src/contexts/deploy/infrastructure/adapters/browser-opener.ts";
import { HERMES_FLY_TS_VERSION } from "../../src/version.ts";
import type {
  DiscordBotAuthPort,
  DiscordBotValidationResult,
} from "../../src/contexts/deploy/infrastructure/adapters/discord-bot-auth.ts";

type MockOutputOptions = {
  isTTY?: boolean;
  columns?: number;
};

function makeIO(opts: { stdout?: MockOutputOptions; stderr?: MockOutputOptions } = {}) {
  const outLines: string[] = [];
  const errLines: string[] = [];
  const stdout = {
    write: (s: string) => { outLines.push(s); },
    isTTY: opts.stdout?.isTTY ?? true,
    columns: opts.stdout?.columns ?? 80,
  };
  const stderr = {
    write: (s: string) => { errLines.push(s); },
    isTTY: opts.stderr?.isTTY ?? true,
    columns: opts.stderr?.columns ?? 80,
  };
  return {
    stdout,
    stderr,
    get outText() { return outLines.join(""); },
    get errText() { return errLines.join(""); },
    get text() { return errLines.join(""); }
  };
}

function maxRenderedWidth(rendered: string): number {
  return rendered
    .trimEnd()
    .split("\n")
    .reduce((max, line) => Math.max(max, Array.from(line).length), 0);
}

function stripAnsi(rendered: string): string {
  return rendered.replace(/\u001B\[[0-9;]*m/g, "");
}

async function withMockedTerminalWidth<T>(width: number, fn: () => Promise<T> | T): Promise<T> {
  const stream = process.stderr as NodeJS.WriteStream & { columns?: number };
  const hadOwn = Object.prototype.hasOwnProperty.call(stream, "columns");
  const previous = stream.columns;
  Object.defineProperty(stream, "columns", {
    value: width,
    configurable: true,
  });
  try {
    return await fn();
  } finally {
    if (hadOwn) {
      Object.defineProperty(stream, "columns", {
        value: previous,
        configurable: true,
      });
    } else {
      delete stream.columns;
    }
  }
}

async function withMockedEnvVar<T>(
  name: string,
  value: string | undefined,
  fn: () => Promise<T> | T
): Promise<T> {
  const hadOwn = Object.prototype.hasOwnProperty.call(process.env, name);
  const previous = process.env[name];
  if (typeof value === "undefined") {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
  try {
    return await fn();
  } finally {
    if (hadOwn) {
      process.env[name] = previous;
    } else {
      delete process.env[name];
    }
  }
}

function itWithAnsiTerminal(name: string, fn: () => Promise<void> | void): void {
  it(name, async () => {
    await withMockedEnvVar("TERM", "xterm-256color", fn);
  });
}

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

function makePort(overrides: Partial<DeployWizardPort> = {}): DeployWizardPort {
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
    finalizeMessagingSetup: async () => ({}),
    chooseSuccessfulDeploymentAction: async () => "conclude",
    showTelegramBotDeletionGuidance: async () => {},
    ...overrides
  };
}

function makeCleanupPort(overrides: Partial<PostDeployCleanupPort> = {}): PostDeployCleanupPort {
  return {
    destroyDeployment: async () => ({ ok: true }),
    ...overrides
  };
}

function makeProcessRunner(
  impl: (
    command: string,
    args: string[],
    options?: { cwd?: string; env?: NodeJS.ProcessEnv }
  ) => Promise<{ stdout?: string; stderr?: string; exitCode: number }>,
  foregroundImpl: (
    command: string,
    args: string[],
    options?: { cwd?: string; env?: NodeJS.ProcessEnv }
  ) => Promise<{ exitCode: number }> = async () => ({ exitCode: 0 }),
  streamingImpl: (
    command: string,
    args: string[],
    options?: {
      cwd?: string;
      env?: NodeJS.ProcessEnv;
      onStdoutChunk?: (chunk: string) => void;
      onStderrChunk?: (chunk: string) => void;
    }
  ) => Promise<{ exitCode: number }> = async () => ({ exitCode: 0 })
): ForegroundProcessRunner {
  return {
    run: async (command, args, options) => {
      const result = await impl(command, args, options);
      if (
        command === "fly"
        && args[0] === "orgs"
        && args[1] === "list"
        && result.exitCode !== 0
        && (result.stdout ?? "") === ""
        && (result.stderr ?? "") === ""
      ) {
        return {
          stdout: JSON.stringify([{ name: "Personal", slug: "personal", type: "PERSONAL" }]),
          stderr: "",
          exitCode: 0
        };
      }
      return {
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? "",
        exitCode: result.exitCode
      };
    },
    runStreaming: async (command, args, options) => streamingImpl(command, args, options),
    runForeground: async (command, args, options) => foregroundImpl(command, args, options)
  };
}

function isFlyCommand(command: string): boolean {
  return command === "fly" || command.endsWith("/fly");
}

function makePromptPort(
  answers: string[],
  opts: { interactive?: boolean; columns?: number } = {}
): DeployPromptPort & {
  asked: string[];
  secretAsked: string[];
  pauses: string[];
  writes: string[];
  selections: Array<{ initialIndex: number; optionCount: number }>;
  multiSelections: Array<{ initialIndex: number; optionCount: number; initialSelectedIndices: number[] }>;
} {
  const asked: string[] = [];
  const secretAsked: string[] = [];
  const pauses: string[] = [];
  const writes: string[] = [];
  const selections: Array<{ initialIndex: number; optionCount: number }> = [];
  const multiSelections: Array<{ initialIndex: number; optionCount: number; initialSelectedIndices: number[] }> = [];
  const nextAnswer = (kind: string, prompt: string): string => {
    if (answers.length === 0) {
      throw new Error(`No scripted answer left for ${kind}: ${prompt}`);
    }
    return answers.shift() ?? "";
  };
  return {
    asked,
    secretAsked,
    pauses,
    writes,
    selections,
    multiSelections,
    isInteractive: () => opts.interactive ?? true,
    columns: () => opts.columns ?? process.stderr.columns ?? 80,
    write: (message: string) => { writes.push(message); },
    ask: async (message: string) => {
      asked.push(message);
      return nextAnswer("ask", message);
    },
    askSecret: async (message: string) => {
      secretAsked.push(message);
      return nextAnswer("askSecret", message);
    },
    selectChoice: async <T>(params: {
      options: Array<{ value: T }>;
      initialIndex: number;
      render: (activeIndex: number) => string;
    }) => {
      selections.push({ initialIndex: params.initialIndex, optionCount: params.options.length });
      const answer = nextAnswer("selectChoice", params.render(params.initialIndex)).trim();
      let selectedIndex = params.initialIndex;
      if (answer.length === 0) {
        writes.push(params.render(selectedIndex));
        return params.options[selectedIndex - 1]?.value;
      }
      const numeric = Number(answer);
      if (Number.isInteger(numeric) && numeric >= 1 && numeric <= params.options.length) {
        selectedIndex = numeric;
      } else {
        const matchedIndex = params.options.findIndex((option) => String(option.value) === answer);
        if (matchedIndex >= 0) {
          selectedIndex = matchedIndex + 1;
        }
      }
      writes.push(params.render(selectedIndex));
      return params.options[selectedIndex - 1]?.value;
    },
    selectManyChoices: async <T>(params: {
      options: Array<{ value: T }>;
      initialIndex: number;
      initialSelectedIndices?: number[];
      render: (activeIndex: number, selectedIndices: number[]) => string;
      normalizeSelectedIndices?: (selectedIndices: number[], activeIndex: number) => number[];
      validateSelectedIndices?: (selectedIndices: number[]) => string | undefined;
    }) => {
      multiSelections.push({
        initialIndex: params.initialIndex,
        optionCount: params.options.length,
        initialSelectedIndices: [...(params.initialSelectedIndices ?? [])],
      });
      while (true) {
        const answer = nextAnswer("selectManyChoices", params.render(params.initialIndex, params.initialSelectedIndices ?? [])).trim();
        let selectedIndices = [...(params.initialSelectedIndices ?? [])];
        if (answer.length > 0) {
          const parts = answer.split(",").map((value) => value.trim()).filter(Boolean);
          const numeric = parts
            .map((value) => Number(value))
            .filter((value) => Number.isInteger(value) && value >= 1 && value <= params.options.length);
          if (numeric.length > 0) {
            selectedIndices = [...new Set(numeric)];
          } else {
            selectedIndices = params.options
              .map((option, index) => (parts.includes(String(option.value)) ? index + 1 : null))
              .filter((value): value is number => value !== null);
          }
        }
        const validationError = params.validateSelectedIndices?.(selectedIndices);
        if (validationError) {
          writes.push(`${validationError}\n`);
          continue;
        }
        if (params.normalizeSelectedIndices) {
          selectedIndices = params.normalizeSelectedIndices(
            selectedIndices,
            selectedIndices.at(-1) ?? params.initialIndex
          );
        }
        writes.push(params.render(params.initialIndex, selectedIndices));
        return selectedIndices.map((index) => params.options[index - 1]?.value).filter((value): value is T => value !== undefined);
      }
    },
    pause: async (message: string) => {
      pauses.push(message);
    }
  };
}

function makeQrRenderer(output = "[[QR: https://t.me/BotFather?text=%2Fnewbot]]"): QrCodeRendererPort {
  return {
    render: async () => output
  };
}

function makeBrowserOpener(result: { ok: boolean; error?: string } = { ok: true }) {
  const opened: string[] = [];
  const opener: BrowserOpenerPort = {
    open: async (url: string) => {
      opened.push(url);
      return result;
    }
  };
  return { opener, opened };
}

function makeDiscordAuth(results: DiscordBotValidationResult[]) {
  const seenTokens: string[] = [];
  const auth: DiscordBotAuthPort = {
    validateBotToken: async (token: string) => {
      seenTokens.push(token);
      const next = results.shift();
      if (!next) {
        throw new Error("No Discord auth result queued");
      }
      return next;
    }
  };
  return { auth, seenTokens };
}

function liveOpenRouterModelsFixture() {
  return [
    {
      id: "anthropic/claude-sonnet-4",
      name: "Anthropic: Claude Sonnet 4",
      supported_parameters: ["max_tokens", "temperature"]
    },
    {
      id: "anthropic/claude-haiku-4.5",
      name: "Anthropic: Claude Haiku 4.5",
      supported_parameters: ["max_tokens", "temperature"]
    },
    {
      id: "openai/gpt-5-mini",
      name: "OpenAI: GPT-5 Mini",
      supported_parameters: ["max_tokens", "temperature", "reasoning", "include_reasoning"]
    },
    {
      id: "openai/gpt-5",
      name: "OpenAI: GPT-5",
      supported_parameters: ["max_tokens", "temperature", "reasoning", "include_reasoning"]
    },
    {
      id: "openai/gpt-5-pro",
      name: "OpenAI: GPT-5 Pro",
      supported_parameters: ["max_tokens", "reasoning", "include_reasoning"]
    },
    {
      id: "openai/o3",
      name: "OpenAI: o3",
      supported_parameters: ["max_tokens", "reasoning", "include_reasoning"]
    },
    {
      id: "openai/gpt-4o",
      name: "OpenAI: GPT-4o",
      supported_parameters: ["max_tokens", "temperature"]
    },
    {
      id: "google/gemini-2.5-flash",
      name: "Google: Gemini 2.5 Flash",
      supported_parameters: ["max_tokens", "temperature"]
    },
    {
      id: "meta-llama/llama-4-maverick",
      name: "Meta: Llama 4 Maverick",
      supported_parameters: ["max_tokens", "temperature"]
    },
    {
      id: "mistralai/mistral-large",
      name: "Mistral: Mistral Large",
      supported_parameters: ["max_tokens", "temperature"]
    }
  ];
}

function liveCodexModelsFixture() {
  return {
    models: [
      { slug: "gpt-5.4", priority: 1 },
      { slug: "gpt-5.3-codex", priority: 2 },
      { slug: "gpt-5.1-codex-mini", priority: 3 },
      { slug: "hidden-model", priority: 4, visibility: "hidden" }
    ]
  };
}

function liveNousModelsFixture() {
  return {
    data: [
      { id: "gpt-5.4" },
      { id: "gpt-5.4-mini" },
      { id: "nous-hermes-3" }
    ]
  };
}

describe("RunDeployWizardUseCase - happy path", () => {
  it("returns ok when all phases pass", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort());
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);
    assert.equal(result.kind, "ok");
  });

  it("saves app after successful deploy", async () => {
    const saved: DeployConfig[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      saveApp: async (config) => { saved.push(config); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);
    assert.equal(saved.length, 1);
    assert.equal(saved[0].appName, "test-app");
    assert.equal(saved[0].region, "iad");
  });

  it("persists WhatsApp binding only after successful pairing and keep action", async () => {
    const saved: DeployConfig[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        messagingPlatforms: ["whatsapp"],
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappCompleteAccessDuringSetup: true,
      }),
      saveApp: async (config) => { saved.push(config); },
      finalizeMessagingSetup: async () => ({ whatsappSessionConfirmed: true }),
      chooseSuccessfulDeploymentAction: async () => "conclude",
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.equal(saved.length, 2);
    assert.equal(saved[0].whatsappSessionConfirmed, undefined);
    assert.equal(saved[1].whatsappSessionConfirmed, true);
  });

  it("prints a completion summary after a successful deploy", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort());

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.outText, /Deployment complete/);
    assert.match(io.outText, /Deployment summary/);
    assert.match(io.outText, /Fly organization:\s+personal/);
    assert.match(io.outText, /Deployment name:\s+test-app/);
    assert.match(io.outText, /Location:\s+iad/);
    assert.match(io.outText, /AI model:\s+anthropic\/claude-sonnet-4-20250514/);
    assert.match(io.outText, /Next steps/);
    assert.match(io.outText, /hermes-fly status -a test-app/);
    assert.match(io.outText, /hermes-fly logs -a test-app/);
    assert.match(io.outText, /hermes-fly doctor -a test-app/);
  });

  it("falls back to the plain completion summary on narrow terminals", async () => {
    const io = makeIO({ stdout: { columns: 40 } });
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        botToken: "123:abc",
        telegramBotUsername: "testhermesbot",
        telegramBotName: "Test Hermes Bot",
        telegramAllowedUsers: "1467489858",
      })
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.outText, /Deployment complete/);
    assert.match(io.outText, /Deployment summary/);
    assert.match(io.outText, /  Fly organization: personal/);
    assert.match(io.outText, /  Telegram: @testhermesbot/);
    assert.match(io.outText, /Next steps/);
    assert.match(io.outText, /Chat link: https:\/\/t\.me\/testhermesbot\?start=test-app/);
    assert.match(io.outText, /hermes-fly status -a test-app/);
    assert.doesNotMatch(io.outText, /◇  Deployment summary/);
    assert.doesNotMatch(io.outText, /◆  Next steps/);
    assert.doesNotMatch(io.outText, /│/);
  });

  it("falls back to the plain completion summary when stdout is not a tty", async () => {
    await withMockedTerminalWidth(120, async () => {
      const io = makeIO({ stdout: { isTTY: false } });
      const uc = new RunDeployWizardUseCase(makePort({
        collectConfig: async () => ({
          ...DEFAULT_CONFIG,
          botToken: "123:abc",
          telegramBotUsername: "testhermesbot",
          telegramBotName: "Test Hermes Bot",
          telegramAllowedUsers: "1467489858",
        })
      }));

      await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

      assert.match(io.outText, /Deployment summary/);
      assert.match(io.outText, /  Fly organization: personal/);
      assert.match(io.outText, /Next steps/);
      assert.match(io.outText, /Chat link: https:\/\/t\.me\/testhermesbot\?start=test-app/);
      assert.doesNotMatch(io.outText, /◇  Deployment summary/);
      assert.doesNotMatch(io.outText, /◆  Next steps/);
    });
  });

  it("prints the specific post-deploy failure reason when health checks detect instability", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      postDeployCheck: async () => ({
        ok: false,
        error: "recent logs show the app was OOM-killed. Choose Standard (512 MB) or larger for Hermes deployments with messaging gateways.",
      }),
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.errText, /Post-deploy check failed: recent logs show the app was OOM-killed/i);
    assert.match(io.errText, /resume -a test-app/);
  });

  it("prints the Z.AI access label in the completion summary when that provider is deployed", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        provider: "zai",
        apiKey: "glm-live-key",
        apiBaseUrl: "https://api.z.ai/api/coding/paas/v4",
        model: "glm-4.7"
      })
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.outText, /AI access:\s+Z\.AI GLM API key/);
  });

  it("prints telegram bot coordinates after a successful deploy", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        botToken: "123:abc",
        telegramBotUsername: "testhermesbot",
        telegramBotName: "Test Hermes Bot",
        telegramAllowedUsers: "1467489858",
        telegramHomeChannel: "1467489858"
      })
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.outText, /Telegram:\s+@testhermesbot/);
    assert.match(io.outText, /Chat link:\s+https:\/\/t\.me\/testhermesbot\?start=test-app/);
    assert.match(io.outText, /Home channel:\s+1467489858/);
  });

  it("keeps long completion commands and Telegram chat links copyable", async () => {
    const longAppName = `hermes-${"a".repeat(56)}`;
    const longTelegramUsername = `hermes${"bot".repeat(8)}`;
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        appName: longAppName,
        botToken: "123:abc",
        telegramBotUsername: longTelegramUsername,
        telegramBotName: "Long Hermes Bot",
        telegramAllowedUsers: "1467489858",
      })
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.ok(io.outText.includes(`Chat link: https://t.me/${longTelegramUsername}?start=${longAppName}`), io.outText);
    assert.ok(io.outText.includes(`hermes-fly status -a ${longAppName}`), io.outText);
    assert.ok(io.outText.includes(`hermes-fly logs -a ${longAppName}`), io.outText);
    assert.ok(io.outText.includes(`hermes-fly doctor -a ${longAppName}`), io.outText);
  });

  it("uses the caller stdout width when rendering enhanced completion summaries", async () => {
    await withMockedTerminalWidth(120, async () => {
      const io = makeIO({ stdout: { columns: 64 } });
      const uc = new RunDeployWizardUseCase(makePort({
        collectConfig: async () => ({
          ...DEFAULT_CONFIG,
          discordBotToken: "discord-live-token",
          discordApplicationId: "123456789012345678",
          discordBotUsername: "hermes-discord-bot-with-an-intentionally-long-handle",
          discordAllowedUsers: "123456789012345678,987654321098765432",
        })
      }));

      await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

      assert.match(io.outText, /◇  Deployment summary/);
      assert.ok(maxRenderedWidth(io.outText) <= 64, io.outText);
    });
  });

  it("prints Discord, Slack, and WhatsApp details in the completion summary", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        messagingPlatforms: ["discord", "slack", "whatsapp"],
        discordBotToken: "discord-live-token",
        discordApplicationId: "123456789012345678",
        discordBotUsername: "hermes-discord-bot",
        discordUsePairing: true,
        slackBotToken: "xoxb-live",
        slackAppToken: "xapp-live",
        slackTeamName: "Hermes Workspace",
        slackUsePairing: true,
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappCompleteAccessDuringSetup: true,
      })
    }));

    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.match(io.outText, /Discord:\s+@hermes-discord-bot/);
    assert.match(io.outText, /Discord access:\s+Only me \(DM pairing\)/);
    assert.match(io.outText, /Slack:\s+Hermes Workspace/);
    assert.match(io.outText, /Slack access:\s+Only me \(DM pairing\)/);
    assert.match(io.outText, /WhatsApp:\s+Self-chat/);
    assert.match(io.outText, /WhatsApp access:\s+Only me \(detected after pairing\)/);
  });

  it("runs post-deploy messaging finalization after the completion summary", async () => {
    const io = makeIO();
    const steps: string[] = [];
    const uc = new RunDeployWizardUseCase(makePort({
      finalizeMessagingSetup: async () => {
        steps.push("finalize");
        return {};
      },
      chooseSuccessfulDeploymentAction: async () => {
        steps.push("choose");
        return "conclude";
      }
    }));

    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.equal(result.kind, "ok");
    assert.deepEqual(steps, ["finalize", "choose"]);
  });

  it("destroys the new deployment when the user chooses the post-deploy destroy action", async () => {
    const io = makeIO();
    const destroyed: string[] = [];
    const uc = new RunDeployWizardUseCase(
      makePort({
        chooseSuccessfulDeploymentAction: async () => "destroy"
      }),
      makeCleanupPort({
        destroyDeployment: async (appName) => {
          destroyed.push(appName);
          return { ok: true };
        }
      })
    );

    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.equal(result.kind, "ok");
    assert.deepEqual(destroyed, ["test-app"]);
    assert.match(io.outText, /Destroying the deployment you just created/);
  });

  it("shows Telegram delete guidance after destroying a deployment that configured a bot", async () => {
    const io = makeIO();
    let guidanceShown = false;
    const uc = new RunDeployWizardUseCase(
      makePort({
        collectConfig: async () => ({
          ...DEFAULT_CONFIG,
          botToken: "123:abc",
          telegramBotUsername: "testhermesbot"
        }),
        chooseSuccessfulDeploymentAction: async () => "destroy",
        showTelegramBotDeletionGuidance: async () => {
          guidanceShown = true;
        }
      }),
      makeCleanupPort()
    );

    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr, io.stdout);

    assert.equal(result.kind, "ok");
    assert.equal(guidanceShown, true);
  });
});

describe("RunDeployWizardUseCase - preflight failure", () => {
  it("returns failed when platform check fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPlatform: async () => ({ ok: false, error: "Windows not supported" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("returns failed when prerequisites check fails with auto-install disabled", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async (opts) => opts.autoInstall
        ? { ok: true }
        : { ok: false, missing: "fly", autoInstallDisabled: true }
    }));
    const result = await uc.execute({ autoInstall: false, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("outputs auto-install disabled message when prereq check fails without auto-install", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async () => ({ ok: false, missing: "fly", autoInstallDisabled: true })
    }));
    await uc.execute({ autoInstall: false, channel: "stable" }, io.stderr);
    assert.ok(io.text.includes("auto-install disabled") || io.text.includes("fly"), `got: ${io.text}`);
  });

  it("surfaces the exact authentication error when interactive login fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkAuth: async () => ({ ok: false, error: "Fly.io authentication did not complete successfully." })
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.match(io.text, /Fly\.io authentication did not complete successfully\./);
  });
});

describe("RunDeployWizardUseCase - provision failure", () => {
  it("returns failed when provision fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      provisionResources: async () => ({ ok: false, error: "Name already taken" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });
});

describe("RunDeployWizardUseCase - deploy failure with resume hint", () => {
  it("returns failed when fly deploy fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({
        ok: false,
        failure: {
          kind: "generic",
          summary: "Fly.io stopped the deploy before Hermes could finish setup.",
          detail: "fly deploy exited with code 1",
        }
      })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("saves app even when fly deploy fails (preserves resources)", async () => {
    const saved: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({
        ok: false,
        failure: {
          kind: "generic",
          summary: "Fly.io stopped the deploy before Hermes could finish setup.",
          detail: "fly deploy exited with code 1",
        }
      }),
      saveApp: async (appName) => { saved.push(appName); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(saved.length, 1, "app should be saved even on deploy failure");
  });

  it("prints actionable capacity guidance and avoids the resume hint when Fly has no room for the machine", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => ({
        ...DEFAULT_CONFIG,
        region: "ams",
        vmSize: "shared-cpu-2x",
        messagingPlatforms: ["whatsapp"],
        whatsappEnabled: true,
        whatsappMode: "self-chat",
      }),
      runDeploy: async () => ({
        ok: false,
        failure: {
          kind: "capacity",
          summary: "Fly.io could not find room for a new server in that region right now.",
          detail: "insufficient memory available to fulfill request",
          suggestedVmSize: "performance-1x",
        }
      })
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.match(io.errText, /Fly\.io could not find room for a new server in that region right now\./);
    assert.match(io.errText, /Fly\.io said: insufficient memory available to fulfill request/);
    assert.match(io.errText, /Try the same deploy again in a few minutes\./);
    assert.match(io.errText, /If it keeps failing, rerun deploy and choose a different region\./);
    assert.match(io.errText, /If you want a safer default, choose Pro \(2 GB\)\./);
    assert.doesNotMatch(io.errText, /resume -a test-app/);
  });
});

describe("RunDeployWizardUseCase - config collection failure", () => {
  it("returns failed when collectConfig throws", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => {
        throw new Error("OPENROUTER_API_KEY is required in non-interactive mode");
      }
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("fails before provisioning when collectConfig throws", async () => {
    const provisioned: boolean[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => {
        throw new Error("OPENROUTER_API_KEY is required in non-interactive mode");
      },
      provisionResources: async () => { provisioned.push(true); return { ok: true }; }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(provisioned.length, 0, "provisioning must not run when config collection fails");
  });

  it("prints a friendly cancellation message when the guided setup is cancelled", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async () => {
        throw new Error("Deployment cancelled.");
      }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(io.text.trim(), "Deployment cancelled.");
  });
});

describe("RunDeployWizardUseCase - channel resolution", () => {
  it("passes stable channel to collectConfig", async () => {
    const captured: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async (opts) => {
        captured.push(opts.channel);
        return { ...DEFAULT_CONFIG, channel: opts.channel };
      }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(captured[0], "stable");
  });

  it("normalizes invalid channel to stable", async () => {
    const captured: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async (opts) => {
        captured.push(opts.channel);
        return { ...DEFAULT_CONFIG, channel: opts.channel };
      }
    }));
    await uc.execute({ autoInstall: true, channel: "invalid" as "stable" }, io.stderr);
    assert.equal(captured[0], "stable");
  });
});

describe("FlyDeployWizard.checkPrerequisites", () => {
  it("does not require OPENROUTER_API_KEY before entering the wizard", async () => {
    const dir = await mkdtemp(join(tmpdir(), "fly-check-"));
    const runner = makeProcessRunner(async (command, args) => {
      if (command.endsWith("/fly")) {
        assert.deepEqual(args, ["version"]);
        return { exitCode: 0, stdout: "fly v0.3.52 linux/amd64\n" };
      }
      throw new Error(`unexpected call: ${command} ${args.join(" ")}`);
    });
    const prompts = makePromptPort([], { interactive: false });
    const { chmod, writeFile } = await import("node:fs/promises");
    await writeFile(join(dir, "fly"), "#!/usr/bin/env bash\nexit 0\n", "utf8");
    await chmod(join(dir, "fly"), 0o755);
    const wizard = new FlyDeployWizard({
      PATH: dir,
      HERMES_FLY_DEFAULT_APP_NAME: "hermes-agent-test"
    }, { process: runner, prompts });

    try {
      const result = await wizard.checkPrerequisites({ autoInstall: true });
      assert.deepEqual(result, { ok: true });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("auto-installs fly when missing and auto-install is enabled", async () => {
    const homeDir = await mkdtemp(join(tmpdir(), "fly-home-"));
    const pathDir = await mkdtemp(join(tmpdir(), "fly-path-"));
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({
      HOME: homeDir,
      PATH: `${pathDir}:/usr/bin:/bin`,
      HERMES_FLY_DEFAULT_APP_NAME: "hermes-agent-test",
      HERMES_FLY_FLYCTL_INSTALL_CMD: `mkdir -p "${homeDir}/.fly/bin" && cat > "${homeDir}/.fly/bin/fly" <<'EOF2'
#!/usr/bin/env bash
if [[ "\${1:-}" == "version" ]]; then
  echo "fly v0.3.52 linux/amd64"
  exit 0
fi
exit 0
EOF2
chmod +x "${homeDir}/.fly/bin/fly"`
    }, { prompts });

    try {
      const result = await wizard.checkPrerequisites({ autoInstall: true });
      assert.deepEqual(result, { ok: true });
      assert.match(prompts.writes.join(""), /Installing it now|installed successfully/);
    } finally {
      await rm(homeDir, { recursive: true, force: true });
      await rm(pathDir, { recursive: true, force: true });
    }
  });

  it("uses a non-login shell for automatic fly installation", async () => {
    const pathDir = await mkdtemp(join(tmpdir(), "fly-missing-"));
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner = makeProcessRunner(async (command, args) => {
      calls.push({ command, args });
      if (command === "bash") {
        return { exitCode: 1, stderr: "permission denied" };
      }
      throw new Error(`unexpected call: ${command} ${args.join(" ")}`);
    });
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({
      HOME: "/tmp/home",
      PATH: pathDir,
      HERMES_FLY_FLYCTL_INSTALL_CMD: "echo install-fly"
    }, { process: runner, prompts });

    const result = await wizard.checkPrerequisites({ autoInstall: true });

    try {
      assert.equal(result.ok, false);
      assert.equal(result.missing, "fly");
      assert.match(result.error ?? "", /permission denied/);
      assert.deepEqual(calls, [{ command: "bash", args: ["-c", "echo install-fly"] }]);
    } finally {
      await rm(pathDir, { recursive: true, force: true });
    }
  });

  it("forces a safe UTF-8 locale for deploy child processes", async () => {
    const pathDir = await mkdtemp(join(tmpdir(), "fly-locale-"));
    let capturedEnv: NodeJS.ProcessEnv | undefined;
    const runner = makeProcessRunner(async (command, args, options) => {
      capturedEnv = options?.env;
      if (command === "bash") {
        return { exitCode: 1, stderr: "permission denied" };
      }
      throw new Error(`unexpected call: ${command} ${args.join(" ")}`);
    });
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({
      HOME: "/tmp/home",
      PATH: pathDir,
      LANG: "broken-locale",
      LC_ALL: "broken-locale",
      HERMES_FLY_FLYCTL_INSTALL_CMD: "echo install-fly"
    }, { process: runner, prompts });

    try {
      await wizard.checkPrerequisites({ autoInstall: true });
      assert.equal(capturedEnv?.LANG, "C");
      assert.equal(capturedEnv?.LC_ALL, "C");
    } finally {
      await rm(pathDir, { recursive: true, force: true });
    }
  });
});

describe("FlyDeployWizard.checkAuth", () => {
  it("runs fly auth login in the current terminal and retries auth", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner = makeProcessRunner(async (command, args) => {
      calls.push({ command, args });
      assert.equal(command, "fly");
      assert.deepEqual(args, ["auth", "whoami"]);
      return {
        exitCode: calls.filter((call) => call.command === "fly" && call.args[0] === "auth" && call.args[1] === "whoami").length === 1 ? 1 : 0
      };
    }, async (command, args) => {
      calls.push({ command, args });
      assert.equal(command, "fly");
      assert.deepEqual(args, ["auth", "login"]);
      return { exitCode: 0 };
    });
    const prompts = makePromptPort([], { interactive: true });
    const wizard = new FlyDeployWizard({}, { process: runner, prompts });

    const result = await wizard.checkAuth();

    assert.deepEqual(result, { ok: true });
    assert.deepEqual(calls, [
      { command: "fly", args: ["auth", "whoami"] },
      { command: "fly", args: ["auth", "login"] },
      { command: "fly", args: ["auth", "whoami"] }
    ]);
    assert.match(prompts.writes.join(""), /browser window may open/i);
  });

  it("returns a targeted error when interactive fly auth login fails", async () => {
    const calls: Array<{ command: string; args: string[] }> = [];
    const runner = makeProcessRunner(async (command, args) => {
      calls.push({ command, args });
      assert.equal(command, "fly");
      assert.deepEqual(args, ["auth", "whoami"]);
      return { exitCode: 1 };
    }, async (command, args) => {
      calls.push({ command, args });
      assert.equal(command, "fly");
      assert.deepEqual(args, ["auth", "login"]);
      return { exitCode: 1 };
    });
    const prompts = makePromptPort([], { interactive: true });
    const wizard = new FlyDeployWizard({}, { process: runner, prompts });

    const result = await wizard.checkAuth();

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /did not complete successfully/);
    assert.deepEqual(calls, [
      { command: "fly", args: ["auth", "whoami"] },
      { command: "fly", args: ["auth", "login"] }
    ]);
  });
});

describe("FlyDeployWizard.runDeploy", () => {
  it("streams fly deploy from the build directory so users still see live output and entrypoint.sh is inside the Docker build context", async () => {
    const calls: Array<{ command: string; args: string[]; cwd?: string }> = [];
    const runner = makeProcessRunner(
      async () => ({ exitCode: 0 }),
      async (command, args, options) => {
        calls.push({ command, args, cwd: options?.cwd });
        return { exitCode: 0 };
      },
      async (command, args, options) => {
        calls.push({ command, args, cwd: options?.cwd });
        return { exitCode: 0 };
      }
    );
    const wizard = new FlyDeployWizard({}, {
      process: runner,
      stdout: { write: () => {} },
      stderr: { write: () => {} },
    });

    const result = await wizard.runDeploy("/tmp/hermes-build", DEFAULT_CONFIG);

    assert.deepEqual(result, { ok: true });
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.command, "fly");
    assert.deepEqual(calls[0]?.args, [
      "deploy", "--app", "test-app", "--config", "fly.toml", "--dockerfile", "Dockerfile", "--wait-timeout", "5m0s"
    ]);
    assert.equal(calls[0]?.cwd, "/tmp/hermes-build");
  });

  it("classifies Fly capacity failures from streamed deploy output", async () => {
    const runner = makeProcessRunner(
      async () => ({ exitCode: 0 }),
      async () => ({ exitCode: 0 }),
      async (command, args, options) => {
        assert.equal(command, "fly");
        assert.deepEqual(args, [
          "deploy", "--app", "test-app", "--config", "fly.toml", "--dockerfile", "Dockerfile", "--wait-timeout", "5m0s"
        ]);
        options?.onStderrChunk?.(
          "Error: error creating a new machine: failed to launch VM: aborted: insufficient resources available to fulfill request: could not reserve resource for machine: insufficient memory available to fulfill request\n"
        );
        return { exitCode: 1 };
      }
    );
    const wizard = new FlyDeployWizard({}, {
      process: runner,
      stdout: { write: () => {} },
      stderr: { write: () => {} },
    });

    const result = await wizard.runDeploy("/tmp/hermes-build", {
      ...DEFAULT_CONFIG,
      region: "ams",
      vmSize: "shared-cpu-2x",
    });

    assert.deepEqual(result, {
      ok: false,
      failure: {
        kind: "capacity",
        summary: "Fly.io could not find room for a new server in that region right now.",
        detail: "insufficient memory available to fulfill request",
        suggestedVmSize: "performance-1x",
      }
    });
  });
});

describe("FlyDeployWizard.postDeployCheck", () => {
  it("passes when fly machine list reports a started machine", async () => {
    const runner = makeProcessRunner(async (command, args) => {
      assert.equal(command, "fly");
      if (args[0] === "machine" && args[1] === "list") {
        assert.deepEqual(args, ["machine", "list", "-a", "test-app", "--json"]);
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ id: "machine123", state: "started" }]),
          stderr: ""
        };
      }
      if (args[0] === "logs" && args[1] === "--app") {
        return {
          exitCode: 124,
          stdout: "Hermes gateway booted cleanly\n",
          stderr: ""
        };
      }
      return {
        exitCode: 1,
        stdout: "",
        stderr: ""
      };
    });
    const wizard = new FlyDeployWizard({}, { process: runner });

    const result = await wizard.postDeployCheck("test-app");

    assert.deepEqual(result, { ok: true });
  });

  it("fails when no machine remains started after deploy", async () => {
    let calls = 0;
    const runner = makeProcessRunner(async () => {
      calls += 1;
      return {
        exitCode: 0,
        stdout: JSON.stringify([{ id: "machine123", state: "stopped" }]),
        stderr: ""
      };
    });
    const wizard = new FlyDeployWizard({}, { process: runner });

    const result = await wizard.postDeployCheck("test-app");

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /machine not running after deploy/);
    assert.equal(calls, 4);
  });

  it("fails with a sizing hint when recent logs show the app was OOM-killed", async () => {
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "machine" && args[1] === "list") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ id: "machine123", state: "started" }]),
          stderr: ""
        };
      }
      if (command === "fly" && args[0] === "logs" && args[1] === "--app") {
        return {
          exitCode: 124,
          stdout: "[  220.859111] Out of memory: Killed process 656 (hermes)\nINFO Process appears to have been OOM killed!\n",
          stderr: ""
        };
      }
      return { exitCode: 1, stdout: "", stderr: "" };
    });
    const wizard = new FlyDeployWizard({}, { process: runner });

    const result = await wizard.postDeployCheck("test-app");

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /OOM-killed/i);
    assert.match(result.error ?? "", /512 MB/);
  });

  it("fails when recent logs show the gateway is crash-looping after restart", async () => {
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "machine" && args[1] === "list") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ id: "machine123", state: "started" }]),
          stderr: ""
        };
      }
      if (command === "fly" && args[0] === "logs" && args[1] === "--app") {
        return {
          exitCode: 124,
          stdout: "Another gateway instance is already running (PID 656, HERMES_HOME=~/.hermes).\n❌ Gateway already running (PID 656).\n",
          stderr: ""
        };
      }
      return { exitCode: 1, stdout: "", stderr: "" };
    });
    const wizard = new FlyDeployWizard({}, { process: runner });

    const result = await wizard.postDeployCheck("test-app");

    assert.equal(result.ok, false);
    assert.match(result.error ?? "", /gateway/i);
    assert.match(result.error ?? "", /restart-loop/i);
  });
});

describe("FlyDeployWizard.postDeployActions", () => {
  it("lets the user keep the deployment after a successful deploy", async () => {
    const prompts = makePromptPort(["1"], { interactive: true });
    const wizard = new FlyDeployWizard({}, { prompts });

    const action = await wizard.chooseSuccessfulDeploymentAction(DEFAULT_CONFIG);

    assert.equal(action, "conclude");
    assert.match(prompts.writes.join(""), /What would you like to do next/);
  });

  it("requires a second confirmation before destroying the new deployment", async () => {
    const prompts = makePromptPort(["2", "y"], { interactive: true });
    const wizard = new FlyDeployWizard({}, { prompts });

    const action = await wizard.chooseSuccessfulDeploymentAction({
      ...DEFAULT_CONFIG,
      appName: "fresh-app",
      botToken: "123:abc"
    });

    assert.equal(action, "destroy");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Destroy it now/);
    assert.ok(prompts.asked.some((message) => message.includes("Destroy fresh-app now")));
  });

  it("shows BotFather delete guidance with a prefilled /deletebot link and QR code", async () => {
    const prompts = makePromptPort([], { interactive: true });
    const wizard = new FlyDeployWizard({}, {
      prompts,
      qrRenderer: makeQrRenderer("[[DELETEBOT-QR]]")
    });

    await wizard.showTelegramBotDeletionGuidance({
      ...DEFAULT_CONFIG,
      botToken: "123:abc",
      telegramBotUsername: "testhermesbot"
    });

    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Telegram does not document any Bot API method/);
    assert.match(guidedCopy, /permanently deletes a/);
    assert.match(guidedCopy, /bot\./);
    assert.match(guidedCopy, /https:\/\/t\.me\/BotFather\?text=%2Fdeletebot/);
    assert.match(guidedCopy, /Scan this QR code with your phone to open BotFather/);
    assert.match(guidedCopy, /\/deletebot ready to/);
    assert.match(guidedCopy, /send:/);
    assert.match(guidedCopy, /\[\[DELETEBOT-QR\]\]/);
    assert.match(guidedCopy, /choose @testhermesbot/);
  });

  it("approves Discord DM pairing after deploy", async () => {
    const prompts = makePromptPort(["ABCD1234"], { interactive: true });
    const calls: Array<{ command: string; args: string[] }> = [];
    const io = makeIO();
    const runner = makeProcessRunner(async (command, args) => {
      calls.push({ command, args });
      return { exitCode: 0, stdout: "", stderr: "" };
    });
    const { opener, opened } = makeBrowserOpener();
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, browserOpener: opener });

    await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      discordBotToken: "discord-live-token",
      discordApplicationId: "123456789012345678",
      discordUsePairing: true,
    }, io.stdout, io.stderr);

    const pairingCall = calls.find((call) => call.args.includes("-C"));
    assert.ok(pairingCall);
    const discordRemoteCommand = pairingCall?.args[pairingCall.args.indexOf("-C") + 1] ?? "";
    assert.match(discordRemoteCommand, /pairing/);
    assert.match(discordRemoteCommand, /approve/);
    assert.match(discordRemoteCommand, /discord/);
    assert.match(discordRemoteCommand, /ABCD1234/);
    assert.match(io.outText, /Discord pairing/);
    assert.match(io.outText, /direct message/i);
    assert.deepEqual(opened, ["https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands"]);
  });

  it("preserves raw WhatsApp QR terminal redraws, starts automatic self-chat verification immediately, verifies a real self-chat test, and avoids local-machine guidance afterward", async () => {
    const prompts = makePromptPort(["y"], { interactive: true });
    const io = makeIO();
    const streamingCalls: Array<{ command: string; args: string[] }> = [];
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    let supervisorStartedAt = 100;
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" ")) && /kill -USR1/.test(args.join(" "))) {
          supervisorStartedAt += 1;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" "))) {
          return { exitCode: 0, stdout: `available\n${supervisorStartedAt}\n`, stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"393406844897@s.whatsapp.net\",\"selfNumber\":\"393406844897\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 393406844897@s.whatsapp.net\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console") {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (command, args, options) => {
        streamingCalls.push({ command, args });
        options?.onStdoutChunk?.("⚕ WhatsApp Setup\n");
        options?.onStdoutChunk?.("  Update allowed users? [y/N] ✓ Bridge dependencies already installed\n");
        options?.onStdoutChunk?.("📱 Scan this QR code with WhatsApp on your phone:\n");
        options?.onStdoutChunk?.("▄▄▄▄ QR FRAME 1 ▄▄▄▄\r▄▄▄▄ QR FRAME 2 ▄▄▄▄\r");
        options?.onStdoutChunk?.("Waiting for scan...\r");
        options?.onStdoutChunk?.("{\"level\":50,\"msg\":\"stream errored out\"}\n");
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        options?.onStdoutChunk?.("\n  Next steps:\n");
        options?.onStdoutChunk?.("    1. Start the gateway:  hermes gateway\n");
        options?.onStdoutChunk?.("    2. Open WhatsApp → Message Yourself\n");
        options?.onStdoutChunk?.("  Or install as a service: hermes gateway install\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    const remoteSetupCall = streamingCalls.find((call) => call.args.join(" ").includes("hermes-agent/venv/bin/hermes") && call.args.join(" ").includes("whatsapp"));
    assert.ok(remoteSetupCall);
    const remoteSetupCommand = remoteSetupCall?.args[remoteSetupCall.args.indexOf("-C") + 1] ?? "";
    assert.match(remoteSetupCommand, /printf %s/);
    assert.match(remoteSetupCommand, /WHATSAPP_ENABLED=.*true/);
    assert.match(remoteSetupCommand, /WHATSAPP_MODE=.*self-chat/);
    assert.doesNotMatch(remoteSetupCommand, /WHATSAPP_ALLOWED_USERS=/);
    assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "secrets set --app test-app --stage"));
    assert.ok(backgroundCalls.filter((call) => /kill -USR1/.test(call.args.join(" "))).length >= 2);
    assert.ok(!backgroundCalls.some((call) => call.args.slice(0, 2).join(" ") === "machine restart"));
    assert.ok(backgroundCalls.some((call) => call.args.slice(0, 4).join(" ") === "machine list -a test-app"));
    assert.ok(backgroundCalls.some((call) => /127\.0\.0\.1:3000\/health/.test(call.args.join(" "))));
    assert.ok(backgroundCalls.some((call) => call.args[0] === "logs" && call.args.includes("--no-tail")));
    assert.match(io.outText, /Scan the QR code with WhatsApp on your phone/);
    assert.match(io.outText, /▄▄▄▄ QR FRAME 1 ▄▄▄▄\r▄▄▄▄ QR FRAME 2 ▄▄▄▄\r/);
    assert.doesNotMatch(io.outText, /▄▄▄▄ QR FRAME 1 ▄▄▄▄\n▄▄▄▄ QR FRAME 2 ▄▄▄▄\n/);
    assert.match(io.outText, /WhatsApp pairing credentials were saved on the deployed agent/i);
    assert.match(io.outText, /may still briefly show 'Logging in\.\.\.' or 'Syncing messages\.\.\.'/i);
    assert.match(io.outText, /Applying the paired WhatsApp session to the deployed Hermes app/i);
    assert.match(io.outText, /Configuring the paired WhatsApp account for Hermes self-chat/i);
    assert.match(io.outText, /Starting automatic Hermes self-chat verification now/i);
    assert.match(io.outText, /To finish verification, send a short message to Message yourself now/i);
    assert.match(io.outText, /Hermes self-chat verification passed/i);
    assert.match(io.outText, /Message yourself/);
    assert.doesNotMatch(io.outText, /Update allowed users\?/);
    assert.doesNotMatch(io.outText, /Your phone number \(e\.g\./i);
    assert.doesNotMatch(io.outText, /No allowlist/i);
    assert.doesNotMatch(io.outText, /Start the gateway:  hermes gateway/);
    assert.doesNotMatch(io.outText, /Or install as a service: hermes gateway install/);
    assert.doesNotMatch(io.outText, /stream errored out/);
    assert.ok(!prompts.asked.some((message) => message.includes("WhatsApp pairing code")));
    assert.ok(!prompts.asked.some((message) => message.includes("Run the automatic self-chat verification now?")));
  });

  it("falls back to a full machine restart when the gateway-only WhatsApp restart does not bring the bridge back", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    let supervisorStartedAt = 100;
    let machineRestarted = false;
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" ")) && /kill -USR1/.test(args.join(" "))) {
          supervisorStartedAt += 1;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" "))) {
          return { exitCode: 0, stdout: `available\n${supervisorStartedAt}\n`, stderr: "" };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          machineRestarted = true;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "secrets" && args[1] === "set") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          if (!machineRestarted) {
            return {
              exitCode: 7,
              stdout: "",
              stderr: "Error: ssh shell: Process exited with status 7",
            };
          }
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /PairingStore/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"447871172820@s.whatsapp.net\":true,\"447871172820\":true,\"242137421639836@lid\":true}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 242137421639836@lid\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console") {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("⚕ WhatsApp Setup\n");
        options?.onStdoutChunk?.("📱 Scan this QR code with WhatsApp on your phone:\n");
        options?.onStdoutChunk?.("Waiting for scan...\n");
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    assert.ok(backgroundCalls.some((call) => call.args.slice(0, 2).join(" ") === "machine restart"));
    assert.ok(backgroundCalls.filter((call) => /kill -USR1/.test(call.args.join(" "))).length >= 2);
    assert.doesNotMatch(io.errText, /did not report a connected session after pairing/i);
  });

  it("fails before opening the remote wizard when stale WhatsApp session data already exists", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    let streamed = false;
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console") {
          return {
            exitCode: 0,
            stdout: "has_session\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async () => {
        streamed = true;
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.equal(streamed, false);
    assert.ok(!backgroundCalls.some((call) => call.args.slice(0, 2).join(" ") === "machine restart"));
    assert.match(io.errText, /existing WhatsApp session data was found before first-time pairing/i);
  });

  it("warns clearly when WhatsApp pairing succeeds but no Fly machine ID can be resolved for the restart", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console") {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.ok(!backgroundCalls.some((call) => call.args.slice(0, 2).join(" ") === "machine restart"));
    assert.match(io.errText, /could not determine which Fly machine to restart/i);
  });

  it("warns clearly when WhatsApp pairing succeeds but the WhatsApp bridge never reconnects after restart", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 1,
            stdout: "{\"status\":\"connecting\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "[whatsapp] ⚠ WhatsApp not connected after 30s\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.ok(backgroundCalls.some((call) => /127\.0\.0\.1:3000\/health/.test(call.args.join(" "))));
    assert.ok(backgroundCalls.some((call) => /bridge\.log/.test(call.args.join(" "))));
    assert.match(io.errText, /whatsapp bridge did not report a connected session after pairing/i);
    assert.match(io.errText, /not connected after 30s/i);
    assert.doesNotMatch(io.outText, /WhatsApp setup completed on the deployed agent/);
  });

  it("warns clearly when WhatsApp self-chat is paired but the test message is denied by the runtime allowlist", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"393406844897@s.whatsapp.net\",\"selfNumber\":\"393406844897\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [warning] Unauthorized user: 393406844897@s.whatsapp.net (Alex) on whatsapp\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "🌉 WhatsApp bridge listening on port 3000 (mode: self-chat)\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "393406844897",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.ok(backgroundCalls.some((call) => call.args[0] === "logs"));
    assert.match(io.errText, /self-chat test message reached Hermes, but it was denied as an unauthorized whatsapp user/i);
    assert.match(io.errText, /Unauthorized user/i);
    assert.doesNotMatch(io.outText, /WhatsApp setup completed on the deployed agent/);
  });

  it("warns clearly when the WhatsApp bridge accepts the self-chat test message but Hermes never processes it", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"393406844897@s.whatsapp.net\",\"selfNumber\":\"393406844897\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: [
              "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.accepted\",\"messageId\":\"wamid.test\",\"chatId\":\"393406844897@s.whatsapp.net\",\"bodyPreview\":\"hello\",\"queueLengthBefore\":0}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.queued\",\"messageId\":\"wamid.test\",\"chatId\":\"393406844897@s.whatsapp.net\",\"queueLength\":1}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.poll.drained\",\"count\":1,\"messageIds\":[\"wamid.test\"],\"queueLengthAfterDrain\":0}",
            ].join("\n"),
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "393406844897",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.ok(backgroundCalls.some((call) => /bridge\.log/.test(call.args.join(" "))));
    assert.match(io.errText, /reached the WhatsApp bridge, but Hermes did not process or reply before the timeout/i);
    assert.match(io.errText, /messages\.upsert\.accepted/);
    assert.doesNotMatch(io.outText, /WhatsApp setup completed on the deployed agent/);
  });

  it("warns clearly when the WhatsApp bridge only sees a self-chat message stub without usable content", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const runner: ForegroundProcessRunner = {
      run: async (_command, args) => {
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"393406844897@s.whatsapp.net\",\"selfNumber\":\"393406844897\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.skipped\",\"reason\":\"missing-message-payload\",\"messageId\":\"wamid.stub\",\"messageStubType\":2}\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "393406844897",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.match(io.errText, /bridge only received a message stub without usable content/i);
    assert.match(io.errText, /missing-message-payload/);
    assert.doesNotMatch(io.outText, /WhatsApp setup completed on the deployed agent/);
  });

  it("adopts the paired WhatsApp number as the self-chat identity after QR pairing", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    let supervisorStartedAt = 100;
    const config: DeployConfig = {
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    };
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" ")) && /kill -USR1/.test(args.join(" "))) {
          supervisorStartedAt += 1;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" "))) {
          return { exitCode: 0, stdout: `available\n${supervisorStartedAt}\n`, stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "secrets" && args[1] === "set") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /PairingStore/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"447871172820@s.whatsapp.net\":true,\"447871172820\":true}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 447871172820@s.whatsapp.net\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup(config, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    assert.equal(config.whatsappAllowedUsers, "447871172820");
    assert.ok(backgroundCalls.filter((call) => /kill -USR1/.test(call.args.join(" "))).length >= 2);
    assert.ok(!backgroundCalls.some((call) => call.args.slice(0, 2).join(" ") === "machine restart"));
    const stagedSetCall = backgroundCalls.find((call) => call.args[0] === "secrets" && call.args[1] === "set");
    assert.ok(stagedSetCall);
    assert.ok(stagedSetCall?.args.includes("--stage"));
    assert.ok(stagedSetCall?.args.includes("HERMES_FLY_WHATSAPP_ALLOWED_USERS=447871172820"));
    const persistedStateCall = backgroundCalls.find((call) =>
      call.args[0] === "ssh"
      && call.args[1] === "console"
      && call.args.some((value) => value.includes("self-chat-identity.json"))
      && call.args.some((value) => value.includes("env_values"))
    );
    assert.ok(persistedStateCall, "expected a remote self-chat identity persistence command");
    assert.match(persistedStateCall?.args.join(" ") ?? "", /WHATSAPP_HOME_CHANNEL/);
    assert.match(persistedStateCall?.args.join(" ") ?? "", /WHATSAPP_HOME_CONTACT/);
    assert.match(io.outText, /Configuring the paired WhatsApp account for Hermes self-chat/i);
    assert.match(io.outText, /To finish verification, send a short message to Message yourself now/i);
    assert.doesNotMatch(io.errText, /you configured WhatsApp self-chat/i);
  });

  it("treats post-prompt bridge edit echoes as successful self-chat replies even when app logs only show startup noise", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    let supervisorStartedAt = 100;
    let bridgeLogReads = 0;
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" ")) && /kill -USR1/.test(args.join(" "))) {
          supervisorStartedAt += 1;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" "))) {
          return { exitCode: 0, stdout: `available\n${supervisorStartedAt}\n`, stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /PairingStore/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"447871172820@s.whatsapp.net\":true,\"447871172820\":true,\"242137421639836@lid\":true}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: [
              "2026-03-19T11:48:27Z app[test] [info][Whatsapp] Bridge ready (status: connected)",
              "2026-03-19T11:48:27Z app[test] [info][Whatsapp] Bridge started on port 3000",
            ].join("\n") + "\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          bridgeLogReads += 1;
          if (bridgeLogReads < 3) {
            return {
              exitCode: 0,
              stdout: [
                "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}",
                "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.skipped\",\"reason\":\"protocol-message-no-content\",\"messageId\":\"wamid.protocol\"}",
              ].join("\n"),
              stderr: "",
            };
          }
          return {
            exitCode: 0,
            stdout: [
              "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.skipped\",\"reason\":\"protocol-message-no-content\",\"messageId\":\"wamid.protocol\"}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.accepted\",\"messageId\":\"wamid.test\",\"chatId\":\"242137421639836@lid\",\"bodyPreview\":\"test\",\"queueLengthBefore\":0}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.queued\",\"messageId\":\"wamid.test\",\"chatId\":\"242137421639836@lid\",\"queueLength\":1}",
              "[hermes-whatsapp-bridge] {\"event\":\"messages.update.skipped\",\"messageId\":\"wamid.test\",\"reason\":\"agent-echo\",\"echoType\":\"edit\",\"chatId\":\"242137421639836@lid\",\"targetMessageId\":\"wamid.test\"}",
            ].join("\n"),
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    assert.match(io.outText, /Hermes self-chat verification passed/i);
    assert.equal(io.errText, "");
  });

  it("takes over an older WhatsApp self-chat deployment after QR once the paired number is detected", async () => {
    const dir = await mkdtemp(join(tmpdir(), "whatsapp-post-pair-takeover-"));
    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: old-whatsapp-app",
          "apps:",
          "  - name: old-whatsapp-app",
          "    region: fra",
          "    provider: zai",
          "    platform: whatsapp",
          "    whatsapp_mode: self-chat",
          "    whatsapp_allowed_users: 447871172820",
        ].join("\n") + "\n",
        "utf8"
      );

      const prompts = makePromptPort(["y", ""], { interactive: true });
      const io = makeIO();
      const backgroundCalls: Array<{ command: string; args: string[] }> = [];
      let oldMachineState = "started";
      const config: DeployConfig = {
        ...DEFAULT_CONFIG,
        appName: "test-app",
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappCompleteAccessDuringSetup: true,
      };
      const runner: ForegroundProcessRunner = {
        run: async (command, args) => {
          backgroundCalls.push({ command, args });
          if (args[0] === "apps" && args[1] === "list") {
            return {
              exitCode: 0,
              stdout: JSON.stringify([{ name: "old-whatsapp-app" }, { name: "test-app" }]),
              stderr: "",
            };
          }
          if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
            if (args.includes("old-whatsapp-app")) {
              return { exitCode: 0, stdout: "has_session\n447871172820", stderr: "" };
            }
            return { exitCode: 0, stdout: "empty_session\n", stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "list") {
            if (args.includes("old-whatsapp-app")) {
              return {
                exitCode: 0,
                stdout: JSON.stringify([{ id: "oldmachine", state: oldMachineState, region: "fra" }]),
                stderr: "",
              };
            }
            return {
              exitCode: 0,
              stdout: JSON.stringify([{ id: "newmachine", state: "started", region: "fra" }]),
              stderr: "",
            };
          }
          if (args[0] === "machine" && args[1] === "stop") {
            oldMachineState = "stopped";
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "start") {
            oldMachineState = "started";
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "restart") {
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "secrets" && args[1] === "unset") {
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "secrets" && args[1] === "set") {
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
            return {
              exitCode: 0,
              stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}\n",
              stderr: "",
            };
          }
          if (args[0] === "logs") {
            return {
              exitCode: 0,
              stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 242137421639836@lid\n",
              stderr: "",
            };
          }
          return { exitCode: 0, stdout: "", stderr: "" };
        },
        runStreaming: async (_command, _args, options) => {
          options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
          return { exitCode: 0 };
        },
        runForeground: async () => ({ exitCode: 0 }),
      };
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir }, { prompts, process: runner, sleep: async () => {} });

      const result = await wizard.finalizeMessagingSetup(config, io.stdout, io.stderr);

      assert.deepEqual(result, { whatsappSessionConfirmed: true });
      assert.equal(config.whatsappAllowedUsers, "447871172820");
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 3).join(" ") === "secrets unset WHATSAPP_ENABLED" && call.args.includes("--stage") && call.args.includes("old-whatsapp-app")));
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "machine stop oldmachine -a old-whatsapp-app"));
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "machine start oldmachine -a old-whatsapp-app"));
      assert.ok(backgroundCalls.some((call) => call.args[0] === "secrets" && call.args[1] === "set" && call.args.includes("HERMES_FLY_WHATSAPP_ALLOWED_USERS=447871172820")));
      assert.match(io.outText, /Taking over WhatsApp from deployment old-whatsapp-app/i);
      assert.doesNotMatch(io.errText, /could not disconnect/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("waits for the paired WhatsApp number to appear after restart before watching automatically for the self-chat test", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    let healthReads = 0;
    const runner: ForegroundProcessRunner = {
      run: async (_command, args) => {
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          healthReads += 1;
          if (healthReads < 3) {
            return {
              exitCode: 0,
              stdout: "{\"status\":\"connected\",\"selfJid\":\"\",\"selfNumber\":\"\"}\n",
              stderr: "",
            };
          }
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 447871172820@s.whatsapp.net\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "447871172820",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    assert.equal(healthReads, 3);
    assert.doesNotMatch(io.errText, /could not determine the phone number of the paired WhatsApp account/i);
    assert.match(io.outText, /To finish verification, send a short message to Message yourself now/i);
    assert.match(io.outText, /watching the deployed logs for that message automatically/i);
    assert.ok(!prompts.asked.some((message) => message.includes("Press Enter after sending your self-chat test message")));
  });

  it("falls back to the bridge connection log when /health omits the paired WhatsApp number after restart", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const runner: ForegroundProcessRunner = {
      run: async (_command, args) => {
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"queueLength\":0,\"uptime\":70.825832092}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 447871172820@s.whatsapp.net\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "447871172820",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    assert.doesNotMatch(io.errText, /never reported the paired WhatsApp phone number/i);
    assert.match(io.outText, /To finish verification, send a short message to Message yourself now/i);
    assert.ok(!prompts.asked.some((message) => message.includes("Press Enter after sending your self-chat test message")));
  });

  it("auto-approves the paired WhatsApp self-chat identities before prompting for the self-chat test", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    let supervisorStartedAt = 100;
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" ")) && /kill -USR1/.test(args.join(" "))) {
          supervisorStartedAt += 1;
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /gateway-supervisor\.pid/.test(args.join(" "))) {
          return { exitCode: 0, stdout: `available\n${supervisorStartedAt}\n`, stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /PairingStore/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"447871172820@s.whatsapp.net\":true,\"447871172820\":true,\"242137421639836@lid\":true}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 242137421639836@lid\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "447871172820",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, { whatsappSessionConfirmed: true });
    const seedCall = backgroundCalls.find((call) =>
      call.args[0] === "ssh"
      && call.args[1] === "console"
      && call.args.some((value) => value.includes("whatsapp-approved.json"))
    );
    assert.ok(seedCall, "expected a remote whatsapp-approved.json seed command");
    const joined = seedCall?.args.join(" ") ?? "";
    assert.match(joined, /447871172820@s\.whatsapp\.net/);
    assert.match(joined, /447871172820/);
    assert.match(joined, /242137421639836@lid/);
    const verifyCall = backgroundCalls.find((call) =>
      call.args[0] === "ssh"
      && call.args[1] === "console"
      && call.args.some((value) => value.includes("PairingStore"))
    );
    assert.ok(verifyCall, "expected a PairingStore approval verification command");
    assert.ok(!prompts.asked.some((message) => message.includes("Press Enter after sending your self-chat test message")));
  });

  it("stops before the self-chat test when hermes-fly cannot auto-approve the paired WhatsApp self-chat identity", async () => {
    const prompts = makePromptPort(["y"], { interactive: true });
    const io = makeIO();
    const runner: ForegroundProcessRunner = {
      run: async (_command, args) => {
        if (args[0] === "ssh" && args[1] === "console" && /whatsapp-approved\.json/.test(args.join(" "))) {
          return {
            exitCode: 1,
            stdout: "",
            stderr: "permission denied",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "447871172820",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.match(io.errText, /could not auto-approve the paired WhatsApp self-chat identity|failed to seed WhatsApp self-chat approval|permission denied/i);
    assert.doesNotMatch(io.outText, /Send a short message to Message yourself now/i);
  });

  it("warns clearly when WhatsApp only emits protocol-level self-chat events without queueable message content", async () => {
    const prompts = makePromptPort(["y", ""], { interactive: true });
    const io = makeIO();
    const runner: ForegroundProcessRunner = {
      run: async (_command, args) => {
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" ")) && !/bridge\.log/.test(args.join(" ")) && !/tail -n 80/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "empty_session\n",
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "machine123", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && args[1] === "restart") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "{\"status\":\"connected\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\"}\n",
            stderr: "",
          };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "",
            stderr: "",
          };
        }
        if (args[0] === "ssh" && args[1] === "console" && /bridge\.log/.test(args.join(" "))) {
          return {
            exitCode: 0,
            stdout: "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.skipped\",\"reason\":\"protocol-message-no-content\",\"protocolType\":4,\"messageId\":\"wamid.protocol\",\"messageTypes\":[\"protocolMessage\",\"messageContextInfo\"]}\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "447871172820",
      whatsappCompleteAccessDuringSetup: true,
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.match(io.errText, /protocol-level self-chat events without message content the bridge could queue/i);
    assert.match(io.errText, /protocol-message-no-content/);
    assert.doesNotMatch(io.outText, /WhatsApp setup completed on the deployed agent/);
  });

  it("disconnects older WhatsApp self-chat deployments before pairing a takeover app", async () => {
    const dir = await mkdtemp(join(tmpdir(), "whatsapp-takeover-finalize-"));
    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: old-whatsapp-app",
          "apps:",
          "  - name: old-whatsapp-app",
          "    region: fra",
          "    provider: zai",
          "    platform: whatsapp",
          "    whatsapp_mode: self-chat",
          "    whatsapp_allowed_users: 393406844897",
        ].join("\n") + "\n",
        "utf8"
      );

      const prompts = makePromptPort(["y", ""], { interactive: true });
      const io = makeIO();
      const backgroundCalls: Array<{ command: string; args: string[] }> = [];
      const streamingCalls: Array<{ command: string; args: string[] }> = [];
      let oldMachineState = "started";
      const runner: ForegroundProcessRunner = {
        run: async (command, args) => {
          backgroundCalls.push({ command, args });
          if (args[0] === "secrets" && args[1] === "unset") {
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "ssh" && args[1] === "console" && /rm -rf \/root\/\.hermes\/whatsapp\/session/.test(args.join(" "))) {
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "ssh" && args[1] === "console" && /127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
            return { exitCode: 0, stdout: "{\"status\":\"connected\",\"selfJid\":\"393406844897@s.whatsapp.net\",\"selfNumber\":\"393406844897\"}\n", stderr: "" };
          }
          if (args[0] === "logs") {
            return {
              exitCode: 0,
              stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 393406844897@s.whatsapp.net\n",
              stderr: "",
            };
          }
          if (args[0] === "ssh" && args[1] === "console") {
            return { exitCode: 0, stdout: "empty_session\n", stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "list") {
            if (args.includes("old-whatsapp-app")) {
              return { exitCode: 0, stdout: JSON.stringify([{ id: "oldmachine", state: oldMachineState, region: "fra" }]), stderr: "" };
            }
            return { exitCode: 0, stdout: JSON.stringify([{ id: "newmachine", state: "started", region: "fra" }]), stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "stop") {
            oldMachineState = "stopped";
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          if (args[0] === "machine" && args[1] === "start") {
            oldMachineState = "started";
            return { exitCode: 0, stdout: "", stderr: "" };
          }
          return { exitCode: 0, stdout: "", stderr: "" };
        },
        runStreaming: async (command, args, options) => {
          streamingCalls.push({ command, args });
          options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
          return { exitCode: 0 };
        },
        runForeground: async () => ({ exitCode: 0 }),
      };
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir }, { prompts, process: runner, sleep: async () => {} });

      const result = await wizard.finalizeMessagingSetup({
        ...DEFAULT_CONFIG,
        appName: "test-app",
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappAllowedUsers: "393406844897",
        whatsappCompleteAccessDuringSetup: true,
        whatsappTakeoverAppNames: ["old-whatsapp-app"],
      }, io.stdout, io.stderr);

      assert.deepEqual(result, { whatsappSessionConfirmed: true });
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 3).join(" ") === "secrets unset WHATSAPP_ENABLED" && call.args.includes("--stage")));
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "machine stop oldmachine -a old-whatsapp-app"));
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "machine start oldmachine -a old-whatsapp-app"));
      assert.ok(backgroundCalls.some((call) => call.args.slice(0, 5).join(" ") === "machine restart newmachine -a test-app"));
      assert.ok(streamingCalls.some((call) => call.args.join(" ").includes("whatsapp")));
      const saved = await readFile(join(dir, "config.yaml"), "utf8");
      assert.doesNotMatch(saved, /whatsapp_mode:/);
      assert.doesNotMatch(saved, /whatsapp_allowed_users:/);
      assert.doesNotMatch(saved, /platform: whatsapp/);
      assert.match(io.outText, /Taking over WhatsApp from deployment old-whatsapp-app/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("stages WhatsApp secret removal before recycling the older takeover deployment", async () => {
    const prompts = makePromptPort(["y"], { interactive: true });
    const io = makeIO();
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "secrets" && args[1] === "unset") {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "ssh" && args[1] === "console" && !/127\.0\.0\.1:3000\/health/.test(args.join(" "))) {
          return { exitCode: 0, stdout: "empty_session\n", stderr: "" };
        }
        if (args[0] === "machine" && args[1] === "list") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([{ id: "oldmachine", state: "started", region: "fra" }]),
            stderr: "",
          };
        }
        if (args[0] === "machine" && (args[1] === "stop" || args[1] === "start" || args[1] === "restart")) {
          return { exitCode: 0, stdout: "", stderr: "" };
        }
        if (args[0] === "logs") {
          return {
            exitCode: 0,
            stdout: "2026-03-18T16:55:00Z app[test] [info] [whatsapp] Sending response (42 chars) to 393406844897@s.whatsapp.net\n",
            stderr: "",
          };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async (_command, _args, options) => {
        options?.onStdoutChunk?.("✅ Pairing complete. Credentials saved.\n");
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "393406844897",
      whatsappCompleteAccessDuringSetup: true,
      whatsappTakeoverAppNames: ["old-whatsapp-app"],
    }, io.stdout, io.stderr);

    const unsetCall = backgroundCalls.find((call) => call.args[0] === "secrets" && call.args[1] === "unset");
    assert.ok(unsetCall);
    assert.ok(unsetCall?.args.includes("--stage"));
    assert.ok(!backgroundCalls.some((call) => call.args[0] === "secrets" && call.args[1] === "deploy"));
  });

  it("stops before pairing when takeover cleanup of the older WhatsApp deployment fails", async () => {
    const prompts = makePromptPort(["y"], { interactive: true });
    const io = makeIO();
    let streamed = false;
    const backgroundCalls: Array<{ command: string; args: string[] }> = [];
    const runner: ForegroundProcessRunner = {
      run: async (command, args) => {
        backgroundCalls.push({ command, args });
        if (args[0] === "secrets" && args[1] === "unset") {
          return { exitCode: 1, stdout: "", stderr: "app not found" };
        }
        return { exitCode: 0, stdout: "", stderr: "" };
      },
      runStreaming: async () => {
        streamed = true;
        return { exitCode: 0 };
      },
      runForeground: async () => ({ exitCode: 0 }),
    };
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, sleep: async () => {} });

    const result = await wizard.finalizeMessagingSetup({
      ...DEFAULT_CONFIG,
      appName: "test-app",
      whatsappEnabled: true,
      whatsappMode: "self-chat",
      whatsappAllowedUsers: "393406844897",
      whatsappCompleteAccessDuringSetup: true,
      whatsappTakeoverAppNames: ["old-whatsapp-app"],
    }, io.stdout, io.stderr);

    assert.deepEqual(result, {});
    assert.equal(streamed, false);
    assert.match(io.errText, /could not disconnect WhatsApp from deployment old-whatsapp-app/i);
  });
});

describe("FlyDeployWizard.diagnoseWhatsAppBridgeLog", () => {
  it("treats agent echoes as success when they match the paired self-chat identity", () => {
    const wizard = new FlyDeployWizard({}, { prompts: makePromptPort([], { interactive: true }) });
    const diagnosis = (wizard as unknown as { diagnoseWhatsAppBridgeLog: (logs: string) => { kind: string } }).diagnoseWhatsAppBridgeLog([
      "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}",
      "[hermes-whatsapp-bridge] {\"event\":\"messages.update.skipped\",\"messageId\":\"wamid.test\",\"reason\":\"agent-echo\",\"echoType\":\"edit\",\"chatId\":\"242137421639836@lid\",\"targetMessageId\":\"wamid.test\"}",
    ].join("\n"));

    assert.deepEqual(diagnosis, { kind: "success" });
  });

  it("treats @lid edit echoes as success when only selfJid/selfNumber are known", () => {
    const wizard = new FlyDeployWizard({}, { prompts: makePromptPort([], { interactive: true }) });
    const diagnosis = (wizard as unknown as { diagnoseWhatsAppBridgeLog: (logs: string) => { kind: string } }).diagnoseWhatsAppBridgeLog([
      "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\"}",
      "[hermes-whatsapp-bridge] {\"event\":\"messages.update.skipped\",\"messageId\":\"wamid.test\",\"reason\":\"agent-echo\",\"echoType\":\"edit\",\"chatId\":\"242137421639836@lid\",\"targetMessageId\":\"wamid.test\"}",
    ].join("\n"));

    assert.deepEqual(diagnosis, { kind: "success" });
  });

  it("ignores agent echoes from other chats when bridge identity is known", () => {
    const wizard = new FlyDeployWizard({}, { prompts: makePromptPort([], { interactive: true }) });
    const diagnosis = (wizard as unknown as { diagnoseWhatsAppBridgeLog: (logs: string) => { kind: string } }).diagnoseWhatsAppBridgeLog([
      "[hermes-whatsapp-bridge] {\"event\":\"connection.open\",\"selfJid\":\"447871172820@s.whatsapp.net\",\"selfNumber\":\"447871172820\",\"selfLid\":\"242137421639836@lid\"}",
      "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.accepted\",\"messageId\":\"wamid.test\",\"chatId\":\"242137421639836@lid\",\"bodyPreview\":\"test\",\"queueLengthBefore\":0}",
      "[hermes-whatsapp-bridge] {\"event\":\"messages.upsert.queued\",\"messageId\":\"wamid.test\",\"chatId\":\"242137421639836@lid\",\"queueLength\":1}",
      "[hermes-whatsapp-bridge] {\"event\":\"messages.update.skipped\",\"messageId\":\"wamid.other\",\"reason\":\"agent-echo\",\"echoType\":\"edit\",\"chatId\":\"15551234567@s.whatsapp.net\",\"targetMessageId\":\"wamid.other\"}",
    ].join("\n"));

    assert.deepEqual(diagnosis, { kind: "accepted_but_unhandled" });
  });
});

describe("FlyDeployWizard.collectConfig", () => {
  it("suggests a unique editable deployment name using username and uid", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async () => ({ exitCode: 1 }));
    const wizard = new FlyDeployWizard({
      UID: "1001",
      USER: "sprite"
    }, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.match(config.appName, /^hermes-sprite-1001-[0-9a-f]{4}$/);
    assert.match(prompts.asked[0] ?? "", /Deployment name \[hermes-sprite-1001-[0-9a-f]{4}\]: /);
  });

  it("regenerates the suggested deployment name when the default is already used by one of your Fly apps", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (isFlyCommand(command) && args[0] === "apps" && args[1] === "list" && args[2] === "--json") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "taken-name" }]),
          stderr: ""
        };
      }
      return { exitCode: 1, stdout: "", stderr: "" };
    });
    const wizard = new FlyDeployWizard({
      HERMES_FLY_DEFAULT_APP_NAME: "taken-name"
    }, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.notEqual(config.appName, "taken-name");
    assert.match(config.appName, /^taken-name-[0-9a-f]{4}$/);
    assert.match(prompts.asked[0] ?? "", /Deployment name \[taken-name-[0-9a-f]{4}\]: /);
  });

  it("reprompts before continuing when the chosen deployment name is already used by one of your Fly apps", async () => {
    const prompts = makePromptPort([
      "taken-name",
      "fresh-name",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (isFlyCommand(command) && args[0] === "apps" && args[1] === "list" && args[2] === "--json") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "taken-name" }]),
          stderr: ""
        };
      }
      return { exitCode: 1, stdout: "", stderr: "" };
    });
    const wizard = new FlyDeployWizard({
      UID: "1001",
      USER: "sprite"
    }, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.appName, "fresh-name");
    assert.equal(prompts.asked.filter((message) => message.startsWith("Deployment name [")).length, 2);
    assert.match(prompts.writes.join(""), /already used by one of your Fly apps/i);
  });

  it("uses guided menus and friendly copy in interactive mode", async () => {
    const prompts = makePromptPort([
      "my-app",
      "2",
      "2",
      "1",
      "3",
      "1",
      "sk-live",
      "2",
      "1",
      "1",
      "1",
      "123:abc",
      "y",
      "1",
      "",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { code: "iad", name: "Ashburn, Virginia (US)" },
            { code: "fra", name: "Frankfurt, Germany" },
            { code: "lhr", name: "London, United Kingdom" }
          ])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "shared-cpu-1x", memory_mb: 256 },
            { name: "shared-cpu-2x", memory_mb: 512 },
            { name: "performance-1x", memory_mb: 2048 }
          ])
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: {
              id: 12345,
              is_bot: true,
              first_name: "Hermes Test Bot",
              username: "test_hermes_bot"
            }
          })
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: [
              {
                update_id: 1,
                message: {
                  chat: { id: 12345, type: "private" },
                  from: { id: 12345, is_bot: false }
                }
              }
            ]
          })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, qrRenderer: makeQrRenderer() });

    const config = await wizard.collectConfig({ channel: "preview" });

    assert.equal(config.appName, "my-app");
    assert.equal(config.region, "lhr");
    assert.equal(config.vmSize, "shared-cpu-2x");
    assert.equal(config.volumeSize, 10);
    assert.equal(config.apiKey, "sk-live");
    assert.equal(config.model, "openai/gpt-4.1-mini");
    assert.equal(config.botToken, "123:abc");
    assert.equal(config.telegramAllowedUsers, "12345");
    assert.equal(config.telegramHomeChannel, "12345");
    assert.equal(config.channel, "preview");
    assert.deepEqual(prompts.secretAsked, [
      "OpenRouter API key (required): ",
      "Telegram bot token (required): "
    ]);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, new RegExp(`Hermes Fly ${HERMES_FLY_TS_VERSION.replaceAll(".", "\\.")}`));
    assert.match(guidedCopy, /┌  Hermes Fly deploy/);
    assert.match(guidedCopy, /◇  Guided setup/);
    assert.match(guidedCopy, /Each deployment needs a unique name on Fly\.io/);
    assert.match(guidedCopy, /Where are you \(or most of your users\) located/);
    assert.match(guidedCopy, /Use ↑\/↓ or j\/k to move, then Enter to confirm\./);
    assert.match(guidedCopy, /● Europe\s+2 locations/);
    assert.match(guidedCopy, /● London, United Kingdom\s+lhr/);
    assert.match(guidedCopy, /How powerful should your agent's server be/);
    assert.match(guidedCopy, /● Standard\s+512 MB/);
    assert.match(guidedCopy, /How much storage should your agent have/);
    assert.match(guidedCopy, /● 10 GB\s+~\$1\.50\/mo/);
    assert.match(guidedCopy, /Get your OpenRouter API key at: https:\/\/openrouter\.ai\/settings\/keys/);
    assert.match(guidedCopy, /● OpenRouter API key/);
    assert.match(guidedCopy, /Which AI provider do you want to use through OpenRouter/);
    assert.match(guidedCopy, /Which OpenAI model should your agent use/);
    assert.match(guidedCopy, /Messaging/);
    assert.match(guidedCopy, /Use ↑\/↓ or j\/k to move, then Enter to confirm\./);
    assert.match(guidedCopy, /● Telegram\s+Chat with your agent in Telegram/);
    assert.match(guidedCopy, /○ Skip for now/);
    assert.match(guidedCopy, /1  ○ Telegram now/);
    assert.match(guidedCopy, /2  ● Skip for now/);
    assert.match(guidedCopy, /Do you want to connect Telegram now/);
    assert.match(guidedCopy, /Open BotFather directly with \/newbot prefilled:/);
    assert.match(guidedCopy, /https:\/\/t\.me\/BotFather\?text=%2Fnewbot/);
    assert.match(guidedCopy, /Scan this QR code with your phone to open BotFather/);
    assert.match(guidedCopy, /\/newbot ready to/);
    assert.match(guidedCopy, /send:/);
    assert.match(guidedCopy, /\[\[QR: https:\/\/t\.me\/BotFather\?text=%2Fnewbot\]\]/);
    assert.match(guidedCopy, /tap Send to submit \/newbot/);
    assert.match(guidedCopy, /Review your setup/);
    assert.ok(!prompts.asked.some((message) => message.includes("Choose an area")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a location")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a tier")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a size")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose platform numbers")));
  });

  it("falls back to the plain guided deploy screens on narrow terminals", async () => {
    await withMockedTerminalWidth(60, async () => {
      const prompts = makePromptPort([
        "my-app",
        "2",
        "2",
        "1",
        "2",
        "1",
        "sk-live",
        "2",
        "2",
        "1",
        "1",
        "1",
        "123:abc",
        "y",
        "1",
        "",
        "y",
        "y"
      ], { interactive: true });
      const runner = makeProcessRunner(async (command, args) => {
        if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([
              { code: "iad", name: "Ashburn, Virginia (US)" },
              { code: "lhr", name: "London, United Kingdom" }
            ])
          };
        }
        if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([
              { name: "shared-cpu-1x", memory_mb: 256 },
              { name: "shared-cpu-2x", memory_mb: 512 }
            ])
          };
        }
        if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              ok: true,
              result: {
                id: 12345,
                is_bot: true,
                first_name: "Hermes Test Bot",
                username: "test_hermes_bot"
              }
            })
          };
        }
        if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              ok: true,
              result: [
                {
                  update_id: 1,
                  message: {
                    chat: { id: 12345, type: "private" },
                    from: { id: 12345, is_bot: false }
                  }
                }
              ]
            })
          };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
        }
        return { exitCode: 1 };
      });
      const wizard = new FlyDeployWizard({}, { prompts, process: runner, qrRenderer: makeQrRenderer() });

      const config = await wizard.collectConfig({ channel: "preview" });

      assert.equal(config.appName, "my-app");
      const guidedCopy = stripAnsi(prompts.writes.join(""));
      assert.match(guidedCopy, /Hermes Agent Guided Setup/);
      assert.match(guidedCopy, /I'll walk you through the deployment setup step by step/);
      assert.match(guidedCopy, /Deployment name/);
      assert.doesNotMatch(guidedCopy, /┌  Hermes Fly deploy/);
      assert.doesNotMatch(guidedCopy, /◇  Guided setup/);
      assert.doesNotMatch(guidedCopy, /██╗/);
    });
  });

  it("sizes guided deploy screens from the prompt output width", async () => {
    await withMockedTerminalWidth(120, async () => {
      const prompts = makePromptPort([
        "my-app",
        "2",
        "2",
        "1",
        "2",
        "1",
        "sk-live",
        "2",
        "2",
        "1",
        "1",
        "1",
        "123:abc",
        "y",
        "1",
        "",
        "y",
        "y"
      ], { interactive: true, columns: 60 });
      const runner = makeProcessRunner(async (command, args) => {
        if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([
              { code: "iad", name: "Ashburn, Virginia (US)" },
              { code: "lhr", name: "London, United Kingdom" }
            ])
          };
        }
        if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
          return {
            exitCode: 0,
            stdout: JSON.stringify([
              { name: "shared-cpu-1x", memory_mb: 256 },
              { name: "shared-cpu-2x", memory_mb: 512 }
            ])
          };
        }
        if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              ok: true,
              result: {
                id: 12345,
                is_bot: true,
                first_name: "Hermes Test Bot",
                username: "test_hermes_bot"
              }
            })
          };
        }
        if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              ok: true,
              result: [
                {
                  update_id: 1,
                  message: {
                    chat: { id: 12345, type: "private" },
                    from: { id: 12345, is_bot: false }
                  }
                }
              ]
            })
          };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
        }
        return { exitCode: 1 };
      });
      const wizard = new FlyDeployWizard({}, { prompts, process: runner, qrRenderer: makeQrRenderer() });

      await wizard.collectConfig({ channel: "preview" });

      const guidedCopy = prompts.writes.join("");
      assert.match(guidedCopy, /Hermes Agent Guided Setup/);
      assert.doesNotMatch(guidedCopy, /┌  Hermes Fly deploy/);
      assert.doesNotMatch(guidedCopy, /◇  Guided setup/);
      assert.doesNotMatch(guidedCopy, /██╗/);
    });
  });

  it("does not offer Starter and keeps Standard as the lowest guided tier", async () => {
    const prompts = makePromptPort([
      "my-app",
      "2",
      "2",
      "1",
      "2",
      "1",
      "sk-live",
      "2",
      "1",
      "5",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { code: "iad", name: "Ashburn, Virginia (US)" },
            { code: "fra", name: "Frankfurt, Germany" },
            { code: "lhr", name: "London, United Kingdom" }
          ])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "shared-cpu-1x", memory_mb: 256 },
            { name: "shared-cpu-2x", memory_mb: 512 },
            { name: "performance-1x", memory_mb: 2048 }
          ])
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: {
              id: 12345,
              is_bot: true,
              first_name: "Hermes Test Bot",
              username: "test_hermes_bot"
            }
          })
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: [
              {
                update_id: 1,
                message: {
                  chat: { id: 12345, type: "private" },
                  from: { id: 12345, is_bot: false }
                }
              }
            ]
          })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, qrRenderer: makeQrRenderer() });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.vmSize, "shared-cpu-2x");
    assert.match(prompts.writes.join(""), /How powerful should your agent's server be/);
    assert.match(prompts.writes.join(""), /Standard\s+512 MB/);
    assert.doesNotMatch(prompts.writes.join(""), /Starter\s+256 MB/);
    assert.ok(!prompts.asked.includes("Choose a tier [1]: "));
  });

  it("offers ChatGPT subscription access through OpenAI Codex and can reuse existing Hermes auth", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-fly-codex-auth-"));
    await mkdir(join(home, ".hermes"), { recursive: true });
    await writeFile(join(home, ".hermes", "auth.json"), JSON.stringify({
      version: 1,
      providers: {
        "openai-codex": {
          tokens: {
            access_token: "access-hermes",
            refresh_token: "refresh-hermes"
          },
          last_refresh: "2026-03-17T07:00:00Z",
          auth_mode: "chatgpt"
        }
      },
      active_provider: "openai-codex"
    }), "utf8");

    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "2",
      "",
      "1",
      "2",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "curl" && args.includes("https://chatgpt.com/backend-api/codex/models?client_version=1.0.0")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify(liveCodexModelsFixture())
        };
      }
      return { exitCode: 1 };
    });

    try {
      const wizard = new FlyDeployWizard({ HOME: home }, { prompts, process: runner });

      const config = await wizard.collectConfig({ channel: "stable" });

      assert.equal(config.provider, "openai-codex");
      assert.equal(config.apiKey, "");
      assert.ok(config.authJsonB64);
      assert.equal(config.model, "gpt-5.4");
      assert.equal(config.sttProvider, "local");
      assert.equal(config.sttModel, "base");
      const guidedCopy = prompts.writes.join("");
      assert.match(guidedCopy, /How should Hermes access AI models/);
      assert.match(guidedCopy, /ChatGPT subscription.*OpenAI Codex/);
      assert.match(guidedCopy, /◆  OpenAI Codex login/);
      assert.match(guidedCopy, /1\s+● Reuse it/);
      assert.match(guidedCopy, /2\s+○ Sign in again/);
      assert.match(guidedCopy, /I found an existing Hermes OpenAI Codex login on this machine/);
      assert.match(guidedCopy, /Which OpenAI Codex model should your agent use/);
      assert.match(guidedCopy, /● GPT 5\.4\s+OpenAI Codex model/);
      assert.match(guidedCopy, /○ Bring my own model\s+Enter a model ID manually/);
      assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("guides the user through the OpenAI Codex device-code flow when no saved auth exists", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "2",
      "2",
      "2",
      "2",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command !== "curl") {
        return { exitCode: 1 };
      }
      const target = args.find((value) => value.startsWith("https://"));
      if (target?.includes("/api/accounts/deviceauth/usercode")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            user_code: "ABCD-EFGH",
            device_auth_id: "device-auth-123",
            interval: 0
          })
        };
      }
      if (target?.includes("/api/accounts/deviceauth/token")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            authorization_code: "authorization-code-123",
            code_verifier: "verifier-456"
          })
        };
      }
      if (target?.includes("/oauth/token")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            access_token: "access-device",
            refresh_token: "refresh-device"
          })
        };
      }
      if (target?.includes("https://chatgpt.com/backend-api/codex/models?client_version=1.0.0")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify(liveCodexModelsFixture())
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.provider, "openai-codex");
    assert.ok(config.authJsonB64);
    assert.equal(config.model, "gpt-5.3-codex");
    assert.equal(config.sttProvider, "local");
    assert.equal(config.sttModel, "base");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /◇  OpenAI Codex sign-in/);
    assert.match(guidedCopy, /https:\/\/auth\.openai\.com\/codex\/device/);
    assert.match(guidedCopy, /https:\/\/chatgpt\.com\/#settings\/Security/);
    assert.match(guidedCopy, /Enable device code authorization for Codex/);
    assert.match(guidedCopy, /ABCD-EFGH/);
    assert.match(guidedCopy, /Fetching available Codex models from OpenAI/);
  });

  it("shows Codex security guidance and lets the user retry the OAuth device-code flow after a failure", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-fly-codex-retry-"));
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "2",
      "1",
      "1",
      "2",
      "y",
      "y"
    ], { interactive: true });
    let userCodeAttempts = 0;
    const runner = makeProcessRunner(async (command, args) => {
      if (command !== "curl") {
        return { exitCode: 1 };
      }
      const target = args.find((value) => value.startsWith("https://"));
      if (target?.includes("/api/accounts/deviceauth/usercode")) {
        userCodeAttempts += 1;
        if (userCodeAttempts === 1) {
          return { exitCode: 0, stdout: "" };
        }
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            user_code: "RETRY-CODE",
            device_auth_id: "device-auth-retry",
            interval: 0
          })
        };
      }
      if (target?.includes("/api/accounts/deviceauth/token")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            authorization_code: "authorization-code-retry",
            code_verifier: "verifier-retry"
          })
        };
      }
      if (target?.includes("/oauth/token")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            access_token: "access-retry",
            refresh_token: "refresh-retry"
          })
        };
      }
      if (target?.includes("https://chatgpt.com/backend-api/codex/models?client_version=1.0.0")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify(liveCodexModelsFixture())
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({ HOME: home }, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.provider, "openai-codex");
    assert.ok(config.authJsonB64);
    assert.equal(userCodeAttempts, 2);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /◆  OpenAI Codex sign-in failed/);
    assert.match(guidedCopy, /1\s+● Retry sign-in/);
    assert.match(guidedCopy, /2\s+○ Cancel setup/);
    assert.match(guidedCopy, /https:\/\/chatgpt\.com\/#settings\/Security/);
    assert.match(guidedCopy, /Enable device code authorization for Codex/);
    assert.match(guidedCopy, /Retry sign-in/);
    assert.match(guidedCopy, /RETRY-CODE/);
  });

  it("prompts for Hermes-compatible reasoning effort for Codex GPT-5 models", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-fly-codex-reasoning-"));
    await mkdir(join(home, ".hermes"), { recursive: true });
    await writeFile(join(home, ".hermes", "auth.json"), JSON.stringify({
      version: 1,
      providers: {
        "openai-codex": {
          tokens: {
            access_token: "access-hermes",
            refresh_token: "refresh-hermes"
          },
          last_refresh: "2026-03-17T07:00:00Z",
          auth_mode: "chatgpt"
        }
      },
      active_provider: "openai-codex"
    }), "utf8");

    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "2",
      "1",
      "1",
      "1",
      "5",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "curl" && args.includes("https://chatgpt.com/backend-api/codex/models?client_version=1.0.0")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify(liveCodexModelsFixture())
        };
      }
      return { exitCode: 1 };
    });

    try {
      const wizard = new FlyDeployWizard({ HOME: home }, { prompts, process: runner });

      const config = await wizard.collectConfig({ channel: "stable" });

      assert.equal(config.provider, "openai-codex");
      assert.equal(config.model, "gpt-5.4");
      assert.equal(config.reasoningEffort, "low");
      const guidedCopy = stripAnsi(prompts.writes.join(""));
      assert.match(guidedCopy, /How much extra reasoning effort should Hermes use with this model/);
      assert.match(guidedCopy, /Lower cost and faster responses/);
      assert.match(guidedCopy, /Balanced \(recommended\)/);
      assert.match(guidedCopy, /Higher effort for harder tasks/);
      assert.match(guidedCopy, /Reasoning:\s+low/);
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("offers Nous Portal access and can reuse existing Hermes auth", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-fly-nous-auth-"));
    await mkdir(join(home, ".hermes"), { recursive: true });
    await writeFile(join(home, ".hermes", "auth.json"), JSON.stringify({
      version: 1,
      providers: {
        nous: {
          portal_base_url: "https://portal.nousresearch.com",
          inference_base_url: "https://inference-api.nousresearch.com/v1",
          client_id: "hermes-cli",
          scope: "inference:mint_agent_key",
          token_type: "Bearer",
          access_token: "access-nous",
          refresh_token: "refresh-nous",
          obtained_at: "2026-03-17T07:00:00.000Z",
          expires_at: "2026-03-17T08:00:00.000Z",
          expires_in: 3600,
          tls: { insecure: false, ca_bundle: null },
          agent_key: null,
          agent_key_id: null,
          agent_key_expires_at: null,
          agent_key_expires_in: null,
          agent_key_reused: null,
          agent_key_obtained_at: null
        }
      },
      active_provider: "nous"
    }), "utf8");

    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "3",
      "1",
      "",
      "",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command !== "curl") {
        return { exitCode: 1 };
      }
      const target = args.find((value) => value.startsWith("https://"));
      if (target === "https://portal.nousresearch.com/api/oauth/agent-key") {
        return {
          exitCode: 0,
          stdout: `${JSON.stringify({
            api_key: "agent-key-123",
            inference_base_url: "https://inference-api.nousresearch.com/v1"
          })}\n200`
        };
      }
      if (target === "https://inference-api.nousresearch.com/v1/models") {
        return {
          exitCode: 0,
          stdout: JSON.stringify(liveNousModelsFixture())
        };
      }
      return { exitCode: 1 };
    });

    try {
      const wizard = new FlyDeployWizard({ HOME: home }, { prompts, process: runner });

      const config = await wizard.collectConfig({ channel: "stable" });

      assert.equal(config.provider, "nous");
      assert.equal(config.apiKey, "");
      assert.ok(config.authJsonB64);
      assert.equal(config.model, "gpt-5.4");
      assert.equal(config.reasoningEffort, "medium");
      assert.equal(config.sttProvider, undefined);
      assert.equal(config.sttModel, undefined);
      const guidedCopy = prompts.writes.join("");
      assert.match(guidedCopy, /How should Hermes access AI models/);
      assert.match(guidedCopy, /Nous Portal subscription/);
      assert.match(guidedCopy, /◆  Nous Portal login/);
      assert.match(guidedCopy, /1\s+● Reuse it/);
      assert.match(guidedCopy, /2\s+○ Sign in again/);
      assert.match(guidedCopy, /I found an existing Hermes Nous Portal login on this machine/);
      assert.match(guidedCopy, /Fetching available models from Nous Portal/);
      assert.match(guidedCopy, /Which Nous Portal model should your agent use/);
      assert.match(guidedCopy, /● GPT 5\.4\s+Nous Portal model/);
      assert.match(guidedCopy, /○ Bring my own model\s+Enter a model ID manually/);
      assert.match(guidedCopy, /AI access:\s+Nous Portal OAuth/);
      assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("offers Anthropic OAuth access and can reuse existing Claude Code credentials", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-fly-anthropic-auth-"));
    await mkdir(join(home, ".claude"), { recursive: true });
    await writeFile(join(home, ".claude", ".credentials.json"), JSON.stringify({
      claudeAiOauth: {
        accessToken: "access-claude",
        refreshToken: "refresh-claude",
        expiresAt: 1_900_000_000_000,
      }
    }), "utf8");

    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "4",
      "1",
      "",
      "",
      "5",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async () => ({ exitCode: 1 }));

    try {
      const wizard = new FlyDeployWizard({ HOME: home }, { prompts, process: runner });

      const config = await wizard.collectConfig({ channel: "stable" });

      assert.equal(config.provider, "anthropic");
      assert.equal(config.apiKey, "");
      assert.ok(config.anthropicOauthJsonB64);
      assert.equal(config.model, "claude-sonnet-4-6");
      assert.equal(config.reasoningEffort, "medium");
      assert.equal(config.sttProvider, "local");
      assert.equal(config.sttModel, "base");
      const guidedCopy = prompts.writes.join("");
      assert.match(guidedCopy, /How should Hermes access AI models/);
      assert.match(guidedCopy, /Anthropic subscription/);
      assert.match(guidedCopy, /◆  Anthropic login/);
      assert.match(guidedCopy, /1\s+● Reuse them/);
      assert.match(guidedCopy, /2\s+○ Sign in again/);
      assert.match(guidedCopy, /I found existing Claude Code credentials on this machine/);
      assert.match(guidedCopy, /Which Anthropic model should your agent use/);
      assert.match(guidedCopy, /● Claude Sonnet 4\.6/);
      assert.match(guidedCopy, /○ Bring my own model\s+Enter a model ID manually/);
      assert.match(guidedCopy, /AI access:\s+Anthropic OAuth/);
      assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("offers Z.AI GLM API-key access and detects the matching coding endpoint", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "5",
      "glm-live-key",
      "",
      "5",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command !== "curl") {
        return { exitCode: 1 };
      }

      const target = args.find((value) => value.startsWith("https://"));
      if (target === "https://api.z.ai/api/coding/paas/v4/chat/completions") {
        return {
          exitCode: 0,
          stdout: "{\"id\":\"probe\"}\n200"
        };
      }

      return { exitCode: 1, stderr: "unexpected target" };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.provider, "zai");
    assert.equal(config.apiKey, "glm-live-key");
    assert.equal(config.apiBaseUrl, "https://api.z.ai/api/coding/paas/v4");
    assert.equal(config.model, "glm-4.7");
    assert.equal(config.reasoningEffort, undefined);
    assert.equal(config.sttProvider, undefined);
    assert.equal(config.sttModel, undefined);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /How should Hermes access AI models/);
    assert.match(guidedCopy, /Z\.AI GLM API key/);
    assert.match(guidedCopy, /Coding Plan/);
    assert.match(guidedCopy, /Detecting the matching Z\.AI GLM endpoint/);
    assert.match(guidedCopy, /Global \(Coding Plan\)/);
    assert.match(guidedCopy, /Which Z\.AI GLM model should your agent use/);
    assert.match(guidedCopy, /● GLM 4\.7\s+Recommended for Coding Plan/);
    assert.match(guidedCopy, /○ Bring my own model\s+Enter a model ID manually/);
    assert.match(guidedCopy, /AI access:\s+Z\.AI GLM API key/);
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
  });

  it("rejects an invalid Z.AI API key and reprompts before deploying", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "5",
      "/Users/alex/Desktop/Screenshot · Fly.png",
      "glm-live-key",
      "",
      "5",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command !== "curl") {
        return { exitCode: 1 };
      }

      const authHeader = args.find((value) => value.startsWith("Authorization: Bearer "));
      const target = args.find((value) => value.startsWith("https://"));
      assert.ok(authHeader);
      assert.ok(target);

      if (authHeader.includes("glm-live-key") && target === "https://api.z.ai/api/coding/paas/v4/chat/completions") {
        return {
          exitCode: 0,
          stdout: "{\"id\":\"probe\"}\n200"
        };
      }

      return {
        exitCode: 0,
        stdout: "{\"error\":\"unauthorized\"}\n401"
      };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.provider, "zai");
    assert.equal(config.apiKey, "glm-live-key");
    assert.equal(config.apiBaseUrl, "https://api.z.ai/api/coding/paas/v4");
    assert.deepEqual(prompts.secretAsked, [
      "Z.AI GLM API key (required): ",
      "Z.AI GLM API key (required): ",
    ]);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /This looks like a file path, not a Z\.AI API key/);
    assert.match(guidedCopy, /Detected: Global \(Coding Plan\) endpoint/);
  });

  it("fetches the full OpenRouter provider catalog and lets the user choose a specific model", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "2",
      "3",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.model, "openai/gpt-5-pro");
    assert.equal(config.reasoningEffort, "high");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Get your OpenRouter API key at: https:\/\/openrouter\.ai\/settings\/keys/);
    assert.match(guidedCopy, /Fetching available models from OpenRouter/);
    assert.match(guidedCopy, /Which AI provider do you want to use through OpenRouter/);
    assert.match(guidedCopy, /○ Anthropic\s+Claude models with strong quality/);
    assert.match(guidedCopy, /● OpenAI\s+GPT models with broad general capability/);
    assert.match(guidedCopy, /Anthropic/);
    assert.match(guidedCopy, /OpenAI/);
    assert.match(guidedCopy, /Mistral/);
    assert.match(guidedCopy, /Which OpenAI model should your agent use/);
    assert.match(guidedCopy, /● GPT-5 Pro\s+Higher capability/);
    assert.match(guidedCopy, /○ Bring my own model\s+Enter a model ID manually/);
    assert.match(guidedCopy, /GPT-5 Mini/);
    assert.match(guidedCopy, /GPT-5\s+/);
    assert.match(guidedCopy, /GPT-5 Pro/);
    assert.match(guidedCopy, /GPT-4o/);
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a provider")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
  });

  it("prompts for a Fly.io organization when multiple orgs are available", async () => {
    const prompts = makePromptPort([
      "2",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "1",
      "1",
      "2",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "orgs" && args[1] === "list") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "Personal", slug: "personal", type: "PERSONAL" },
            { name: "Team Deployments", slug: "team-deployments", type: "SHARED" }
          ])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.orgSlug, "team-deployments");
    assert.match(prompts.writes.join(""), /Which Fly\.io organization should own this deployment/);
    assert.ok(!prompts.asked.some((message) => message.includes("Choose an organization")));
    const guidedCopy = stripAnsi(prompts.writes.join(""));
    assert.match(guidedCopy, /○ Personal\s+personal/);
    assert.match(guidedCopy, /● Team Deployments\s+team-deployments/);
    assert.ok(prompts.selections.some((selection) => selection.optionCount === 2 && selection.initialIndex === 1));
  });

  it("renders numbered Fly organization options when selectChoice support is unavailable", async () => {
    const prompts = makePromptPort([
      "2",
      "",
      "1",
      "1",
      "1",
      "1",
      "1",
      "sk-live",
      "1",
      "1",
      "",
      "y"
    ], { interactive: true });
    delete prompts.selectChoice;
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "orgs" && args[1] === "list") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "Personal", slug: "personal", type: "PERSONAL" },
            { name: "Team Deployments", slug: "team-deployments", type: "SHARED" }
          ])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.orgSlug, "team-deployments");
    assert.ok(prompts.asked.includes("Choose an organization [1]: "));
    const guidedCopy = stripAnsi(prompts.writes.join(""));
    assert.match(guidedCopy, /1\s+● Personal\s+personal/);
    assert.match(guidedCopy, /2\s+○ Team Deployments\s+team-deployments/);
    assert.doesNotMatch(guidedCopy, /Use ↑\/↓ or j\/k to move, then Enter to confirm\./);
  });

  it("shows hosting platform availability before Fly organization without adding a new prompt", async () => {
    const prompts = makePromptPort([
      "2",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "1",
      "1",
      "2",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "orgs" && args[1] === "list") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "Personal", slug: "personal", type: "PERSONAL" },
            { name: "Team Deployments", slug: "team-deployments", type: "SHARED" }
          ])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    await wizard.collectConfig({ channel: "stable" });

    const guidedCopy = stripAnsi(prompts.writes.join(""));
    const hostingIndex = guidedCopy.indexOf("Hosting Platform");
    const organizationIndex = guidedCopy.indexOf("Fly organization");

    assert.ok(hostingIndex >= 0, guidedCopy);
    assert.ok(organizationIndex > hostingIndex, guidedCopy);
    assert.match(guidedCopy, /● Fly\.io/);
    assert.match(guidedCopy, /○ \[SOON\] Deploy locally/);
    assert.match(guidedCopy, /○ \[SOON\] Railway\.com/);
    assert.doesNotMatch(prompts.writes.join(""), /\u001B\[[0-9;]*m/);
    assert.ok(!prompts.asked.some((message) => /Choose a hosting platform/i.test(message)));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose an organization")));
    assert.match(guidedCopy, /Which Fly\.io organization should own this deployment\?\n│\n│  If you only use Fly personally/);
    assert.match(guidedCopy, /○ Personal\s+personal/);
    assert.match(guidedCopy, /● Team Deployments\s+team-deployments/);
  });

  it("uses a single-select messaging choice in the interactive selector path", async () => {
    const prompts = makePromptPort(["4"], { interactive: true });
    const wizard = new FlyDeployWizard({}, { prompts });

    const selection = await (wizard as unknown as {
      collectMessagingPlatformsChoice: () => Promise<string[]>;
    }).collectMessagingPlatformsChoice();

    assert.deepEqual(selection, ["whatsapp"]);
    assert.ok(prompts.selections.some((selection) => selection.optionCount === 5 && selection.initialIndex === 5));
    assert.equal(prompts.multiSelections.length, 0);
    const guidedCopy = stripAnsi(prompts.writes.join(""));
    assert.match(guidedCopy, /Use ↑\/↓ or j\/k to move, then Enter to confirm\./);
    assert.match(guidedCopy, /● WhatsApp\s+Chat with your agent in WhatsApp/);
    assert.match(guidedCopy, /○ Skip for now/);
    assert.doesNotMatch(guidedCopy, /Space to toggle/);
  });

  it("renders numbered single-select messaging options when selectChoice support is unavailable", async () => {
    const prompts = makePromptPort(["4"], { interactive: true });
    delete prompts.selectChoice;
    const wizard = new FlyDeployWizard({}, { prompts });

    const selection = await (wizard as unknown as {
      collectMessagingPlatformsChoice: () => Promise<string[]>;
    }).collectMessagingPlatformsChoice();

    assert.deepEqual(selection, ["whatsapp"]);
    const guidedCopy = stripAnsi(prompts.writes.join(""));
    assert.match(guidedCopy, /1\s+○ Telegram\s+Chat with your agent in Telegram/);
    assert.match(guidedCopy, /4\s+○ WhatsApp\s+Chat with your agent in WhatsApp/);
    assert.match(guidedCopy, /5\s+● Skip for now/);
    assert.doesNotMatch(guidedCopy, /You can connect more than one/);
    assert.equal(prompts.asked.filter((message) => message === "Choose a platform [5]: ").length, 1);
  });

  it("shows a direct BotFather link and renders a QR code when Telegram setup is selected", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "2",
      "1",
      "",
      "1",
      "1",
      "123:abc",
      "y",
      "1",
      "",
      "y",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: {
              id: 12345,
              is_bot: true,
              first_name: "Hermes Test Bot",
              username: "test_hermes_bot"
            }
          })
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: [
              {
                update_id: 1,
                message: {
                  chat: { id: 12345, type: "private" },
                  from: { id: 12345, is_bot: false }
                }
              }
            ]
          })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, {
      prompts,
      process: runner,
      qrRenderer: makeQrRenderer("[[BOTFATHER-QR]]")
    });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.botToken, "123:abc");
    assert.equal(config.telegramAllowedUsers, "12345");
    assert.equal(config.telegramHomeChannel, "12345");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Open BotFather directly with \/newbot prefilled:/);
    assert.match(guidedCopy, /https:\/\/t\.me\/BotFather\?text=%2Fnewbot/);
    assert.match(guidedCopy, /Scan this QR code with your phone to open BotFather/);
    assert.match(guidedCopy, /\/newbot ready to/);
    assert.match(guidedCopy, /send:/);
    assert.match(guidedCopy, /\[\[BOTFATHER-QR\]\]/);
    assert.match(guidedCopy, /tap Send to submit \/newbot/);
    assert.match(guidedCopy, /Guide: https:\/\/core\.telegram\.org\/bots#6-botfather/);
    assert.match(guidedCopy, /Found bot: @test_hermes_bot \(Hermes Test Bot\)/);
    assert.match(guidedCopy, /◆  Telegram access/);
    assert.match(guidedCopy, /1\s+● Only me/);
    assert.match(guidedCopy, /2\s+○ Specific people/);
    assert.match(guidedCopy, /◆  Telegram direct chat/);
    assert.match(guidedCopy, /Open your bot directly: https:\/\/t\.me\/test_hermes_bot/);
    assert.match(guidedCopy, /Detected your Telegram user ID: 12345/);
    assert.ok(prompts.asked.some((message) => message.includes("Use 12345 as the home channel")));
  });

  it("live-validates the Telegram token, re-prompts on invalid user ids, and stores specific-user access", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "1",
      "1",
      "1",
      "1",
      "not-a-token",
      "123:abc",
      "y",
      "2",
      "alexfazio",
      "12345,67890",
      "n",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: {
              id: 12345,
              is_bot: true,
              first_name: "Hermes Test Bot",
              username: "test_hermes_bot"
            }
          })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.botToken, "123:abc");
    assert.equal(config.telegramAllowedUsers, "12345,67890");
    assert.equal(config.gatewayAllowAllUsers, undefined);
    assert.equal(config.telegramHomeChannel, undefined);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Telegram bot token format looks invalid/);
    assert.match(guidedCopy, /Verifying your bot token with Telegram/);
    assert.match(guidedCopy, /◆  Telegram access/);
    assert.match(guidedCopy, /user IDs must be numeric/i);
    assert.ok(prompts.asked.some((message) => message.includes("Continue with this bot?")));
  });

  it("guides a non-technical user through Discord bot creation, opens the portal and invite link, and defaults to DM pairing", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "2",
      "2",
      "",
      "discord-live-token",
      "1",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
      }
      return { exitCode: 1 };
    });
    const { auth } = makeDiscordAuth([
      {
        ok: true,
        identity: {
          applicationId: "123456789012345678",
          username: "hermes-discord-bot",
          inviteUrl: "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands",
        },
      },
    ]);
    const { opener, opened } = makeBrowserOpener();
    const wizard = new FlyDeployWizard({}, {
      prompts,
      process: runner,
      discordAuth: auth,
      browserOpener: opener,
      qrRenderer: makeQrRenderer("[[DISCORD-QR]]"),
    });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.deepEqual(config.messagingPlatforms, ["discord"]);
    assert.equal(config.discordBotToken, "discord-live-token");
    assert.equal(config.discordApplicationId, "123456789012345678");
    assert.equal(config.discordBotUsername, "hermes-discord-bot");
    assert.equal(config.discordUsePairing, true);
    assert.equal(config.discordAllowedUsers, undefined);
    assert.deepEqual(opened, [
      "https://discord.com/developers/applications",
      "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands",
    ]);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /If you already have a Discord bot token, you can paste it now/);
    assert.match(guidedCopy, /1  ○ I already have a bot token/);
    assert.match(guidedCopy, /2\s+● Help me create one/);
    assert.match(guidedCopy, /◇  Discord Developer Portal/);
    assert.match(guidedCopy, /New Application/);
    assert.match(guidedCopy, /Add Bot/);
    assert.match(guidedCopy, /Reset Token/);
    assert.match(guidedCopy, /◆  Discord invite/);
    assert.match(guidedCopy, /Invite URL: https:\/\/discord\.com\/oauth2\/authorize\?client_id=123456789012345678&scope=bot%20applications\.commands/);
    assert.match(guidedCopy, /\[\[DISCORD-QR\]\]/);
    assert.match(guidedCopy, /◆  Discord access/);
    assert.match(guidedCopy, /1\s+● Only me/);
    assert.ok(prompts.pauses.some((message) => message.includes("copied the Discord bot token")));
    assert.ok(prompts.pauses.some((message) => message.includes("invited this bot to your Discord server")));
  });

  it("explains likely Discord token mistakes before re-prompting", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "2",
      "1",
      "bad-token",
      "good-token",
      "1",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
      }
      return { exitCode: 1 };
    });
    const { auth, seenTokens } = makeDiscordAuth([
      { ok: false, reason: "invalid_token", error: "TokenInvalid: An invalid token was provided." },
      {
        ok: true,
        identity: {
          applicationId: "123456789012345678",
          username: "hermes-discord-bot",
          inviteUrl: "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands",
        },
      },
    ]);
    const { opener } = makeBrowserOpener();
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, discordAuth: auth, browserOpener: opener });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.discordBotToken, "good-token");
    assert.deepEqual(seenTokens, ["bad-token", "good-token"]);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /◇  Discord token troubleshooting/);
    assert.match(guidedCopy, /Client Secret instead of Bot Token/i);
    assert.match(guidedCopy, /token was regenerated/i);
  });

  it("configures Slack with bot and app tokens plus DM pairing for only-me access", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "3",
      "xoxb-live",
      "xapp-live",
      "y",
      "1",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
      }
      if (command === "curl" && args.includes("https://slack.com/api/auth.test")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ ok: true, team: "Hermes Workspace", user_id: "U123ABC456" })
        };
      }
      if (command === "curl" && args.includes("https://slack.com/api/apps.connections.open")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ ok: true, url: "wss://slack.example/socket" })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.deepEqual(config.messagingPlatforms, ["slack"]);
    assert.equal(config.slackBotToken, "xoxb-live");
    assert.equal(config.slackAppToken, "xapp-live");
    assert.equal(config.slackTeamName, "Hermes Workspace");
    assert.equal(config.slackBotUserId, "U123ABC456");
    assert.equal(config.slackUsePairing, true);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Hermes uses Socket Mode for Slack, so the app token is required/);
    assert.match(guidedCopy, /Connected Slack workspace: Hermes Workspace/);
  });

  it("configures WhatsApp self-chat without asking for a phone number before pairing", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "4",
      "2",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.deepEqual(config.messagingPlatforms, ["whatsapp"]);
    assert.equal(config.whatsappEnabled, true);
    assert.equal(config.whatsappMode, "self-chat");
    assert.equal(config.whatsappAllowedUsers, undefined);
    assert.equal(config.whatsappCompleteAccessDuringSetup, true);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /WhatsApp has two setup styles/);
    assert.match(guidedCopy, /If you are just testing for yourself, pick Self-chat/);
    assert.match(guidedCopy, /If you want other people to talk to Hermes, pick Bot mode/);
    assert.match(guidedCopy, /a dedicated WhatsApp number is the recommended setup/);
    assert.match(guidedCopy, /Hermes will finish WhatsApp pairing after deploy/);
    assert.match(guidedCopy, /opening the remote/);
    assert.match(guidedCopy, /WhatsApp setup flow in this terminal/);
    assert.match(guidedCopy, /Recommended for safe personal testing/);
    assert.match(guidedCopy, /detect the linked WhatsApp account from the QR pairing step/i);
    assert.match(guidedCopy, /You do not need to enter your phone number here/i);
    assert.match(guidedCopy, /Only me \(detected after pairing\)/);
    assert.doesNotMatch(guidedCopy, /Who should be able to talk to your WhatsApp setup/i);
    assert.doesNotMatch(guidedCopy, /Specific people/i);
    assert.doesNotMatch(guidedCopy, /Your WhatsApp number:/i);
  });

  it("keeps the WhatsApp allowlist flow for bot mode", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "4",
      "1",
      "2",
      "+39 340 6844897, +44 7871 172820",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.deepEqual(config.messagingPlatforms, ["whatsapp"]);
    assert.equal(config.whatsappEnabled, true);
    assert.equal(config.whatsappMode, "bot");
    assert.equal(config.whatsappAllowedUsers, "393406844897,447871172820");
    assert.equal(config.whatsappCompleteAccessDuringSetup, undefined);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Who should be able to talk to your WhatsApp setup/i);
    assert.match(guidedCopy, /Specific people\s+Enter the phone numbers that should be allowed/i);
  });

  it("does not probe or warn about self-chat number conflicts before QR pairing", async () => {
    const dir = await mkdtemp(join(tmpdir(), "whatsapp-conflict-"));
    try {
      await writeFile(
        join(dir, "config.yaml"),
        [
          "current_app: old-whatsapp-app",
          "apps:",
          "  - name: old-whatsapp-app",
          "    region: fra",
          "    provider: zai",
          "    platform: whatsapp",
          "    whatsapp_mode: self-chat",
          "    whatsapp_allowed_users: 393406844897",
        ].join("\n") + "\n",
        "utf8"
      );

      const prompts = makePromptPort([
        "",
        "",
        "",
        "",
        "",
        "1",
        "sk-live",
        "",
        "",
        "4",
        "2",
        "y"
      ], { interactive: true });
      let probed = false;
      const runner = makeProcessRunner(async (command, args) => {
        if (isFlyCommand(command) && args[0] === "platform" && args[1] === "regions") {
          return { exitCode: 0, stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }]) };
        }
        if (isFlyCommand(command) && args[0] === "platform" && args[1] === "vm-sizes") {
          return { exitCode: 0, stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }]) };
        }
        if (isFlyCommand(command) && args[0] === "apps" && args[1] === "list") {
          return { exitCode: 0, stdout: JSON.stringify([{ name: "old-whatsapp-app" }]) };
        }
        if (isFlyCommand(command) && args[0] === "ssh" && args[1] === "console") {
          probed = true;
          return { exitCode: 0, stdout: "has_session\n393406844897", stderr: "" };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } }) };
        }
        if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
          return { exitCode: 0, stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() }) };
        }
        return { exitCode: 1 };
      });
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir }, { prompts, process: runner });

      const config = await wizard.collectConfig({ channel: "stable" });

      assert.equal(probed, false);
      assert.deepEqual(config.messagingPlatforms, ["whatsapp"]);
      assert.equal(config.whatsappEnabled, true);
      assert.equal(config.whatsappMode, "self-chat");
      assert.equal(config.whatsappAllowedUsers, undefined);
      assert.equal(config.whatsappTakeoverAppNames, undefined);
      const guidedCopy = prompts.writes.join("");
      assert.doesNotMatch(guidedCopy, /still appears tied with deployment old-whatsapp-app/i);
      assert.doesNotMatch(guidedCopy, /Take over this number/i);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("prompts for Hermes-compatible reasoning effort when the selected model supports it", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "2",
      "2",
      "3",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.model, "openai/gpt-5");
    assert.equal(config.reasoningEffort, "high");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /How much extra reasoning effort should Hermes use with this model/);
    assert.match(guidedCopy, /Lower cost and faster responses/);
    assert.match(guidedCopy, /Balanced \(recommended\)/);
    assert.match(guidedCopy, /Higher effort for harder tasks/);
    assert.match(guidedCopy, /Reasoning:\s+high/);
  });

  it("auto-selects the only Hermes-compatible reasoning effort when a model has one allowed level", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "2",
      "3",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.model, "openai/gpt-5-pro");
    assert.equal(config.reasoningEffort, "high");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Hermes will use the only supported reasoning effort for this model: high\./);
  });

  it("skips the reasoning step when OpenRouter supports reasoning but Hermes has no compatible policy for that model yet", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "2",
      "4",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: liveOpenRouterModelsFixture() })
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.model, "openai/o3");
    assert.equal(config.reasoningEffort, undefined);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /OpenRouter exposes reasoning controls for this model/);
    assert.match(guidedCopy, /Hermes Agent does not yet have a tested reasoning-effort policy for it/);
    assert.doesNotMatch(guidedCopy, /How much extra reasoning effort should Hermes use with this model/);
  });

  it("falls back to a provider-first starter catalog when OpenRouter model fetch fails", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "1",
      "2",
      "",
      "y"
    ], { interactive: true });
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ code: "iad", name: "Ashburn, Virginia (US)" }])
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([{ name: "shared-cpu-1x", memory_mb: 256 }])
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/key")) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({ data: { is_free_tier: false, usage: 10 } })
        };
      }
      if (command === "curl" && args.includes("https://openrouter.ai/api/v1/models")) {
        return {
          exitCode: 28,
          stderr: "operation timed out"
        };
      }
      return { exitCode: 1 };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.model, "anthropic/claude-3-5-haiku");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /I couldn't load the live OpenRouter model list/);
    assert.match(guidedCopy, /Browse every available model at: https:\/\/openrouter\.ai\/models/);
    assert.match(guidedCopy, /Which AI provider do you want to use through OpenRouter/);
    assert.match(guidedCopy, /● Anthropic\s+Claude models with strong quality/);
    assert.match(guidedCopy, /Which Anthropic model should your agent use/);
    assert.match(guidedCopy, /● Claude 3\.5 Haiku\s+Fast and lower cost/);
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a provider")));
    assert.ok(!prompts.asked.some((message) => message.includes("Choose a model")));
  });

  it("uses the pinned Hermes Agent ref for stable deployments", async () => {
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({
      HERMES_FLY_ORG: "personal",
      OPENROUTER_API_KEY: "sk-test",
      HERMES_FLY_MODEL: "anthropic/claude-3-5-sonnet"
    }, { prompts });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.hermesRef, "8eefbef91cd715cfe410bba8c13cfab4eb3040df");
  });

  it("uses the moving main ref only for edge deployments", async () => {
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({
      HERMES_FLY_ORG: "personal",
      OPENROUTER_API_KEY: "sk-test",
      HERMES_FLY_MODEL: "anthropic/claude-3-5-sonnet"
    }, { prompts });

    const config = await wizard.collectConfig({ channel: "edge" });

    assert.equal(config.hermesRef, "main");
  });

  it("fails in non-interactive mode when OPENROUTER_API_KEY is missing", async () => {
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({ HERMES_FLY_ORG: "personal" }, { prompts });

    await assert.rejects(
      wizard.collectConfig({ channel: "stable" }),
      /OPENROUTER_API_KEY is required in non-interactive mode/
    );
  });

  it("lets the user cancel after reviewing the summary", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "1",
      "sk-live",
      "",
      "",
      "",
      "n"
    ], { interactive: true });
    const runner = makeProcessRunner(async () => ({ exitCode: 1 }));
    const wizard = new FlyDeployWizard({ UID: "1001", USER: "sprite" }, { prompts, process: runner });

    await assert.rejects(
      wizard.collectConfig({ channel: "stable" }),
      /Deployment cancelled\./
    );
  });
});

describe("ReadlineDeployPrompts.askSecret", () => {
  it("does not echo the entered secret", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const answerPromise = prompts.askSecret("OpenRouter API key (required): ");
    input.write("sk-hidden");
    input.write("\n");
    const answer = await answerPromise;

    assert.equal(answer, "sk-hidden");
    assert.deepEqual(rawModeTransitions, [true, false]);
    const written = chunks.join("");
    assert.match(written, /OpenRouter API key \(required\): /);
    assert.doesNotMatch(written, /sk-hidden/);
  });
});

describe("ReadlineDeployPrompts.selectChoice", () => {
  it("reads numeric input through readline when stdin is piped", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    Object.assign(input, { isTTY: false });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: () => "● Personal\n○ Team\n",
      renderFallback: (activeIndex) => [
        `${activeIndex === 1 ? "1 ●" : "1 ○"} Personal`,
        `${activeIndex === 2 ? "2 ●" : "2 ○"} Team`,
        "",
      ].join("\n"),
      fallbackPrompt: "Choose an organization [1]: ",
    });
    input.write("2\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /1 ● Personal\n2 ○ Team/);
    assert.match(written, /Choose an organization \[1\]: /);
  });

  it("falls back to numbered input on dumb terminals even when raw mode is available", async () => {
    await withMockedEnvVar("TERM", "dumb", async () => {
      const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
      const rawModeTransitions: boolean[] = [];
      Object.assign(input, {
        isTTY: true,
        setRawMode: (value: boolean) => {
          rawModeTransitions.push(value);
        }
      });

      const chunks: string[] = [];
      const output = new Writable({
        write(chunk, _encoding, callback) {
          chunks.push(chunk.toString());
          callback();
        }
      }) as Writable & NodeJS.WriteStream;
      Object.assign(output, { isTTY: true });

      const prompts = new ReadlineDeployPrompts(input, output);
      const selectionPromise = prompts.selectChoice({
        options: [
          { value: "personal" },
          { value: "team" }
        ],
        initialIndex: 1,
        render: () => "● Personal\n○ Team\n",
        renderFallback: (activeIndex) => [
          `${activeIndex === 1 ? "1 ●" : "1 ○"} Personal`,
          `${activeIndex === 2 ? "2 ●" : "2 ○"} Team`,
          "",
        ].join("\n"),
        fallbackPrompt: "Choose an organization [1]: ",
      });
      input.write("2\n");
      const selection = await selectionPromise;

      assert.equal(selection, "team");
      const written = stripAnsi(chunks.join(""));
      assert.match(written, /1 ● Personal\n2 ○ Team/);
      assert.match(written, /Choose an organization \[1\]: /);
      assert.doesNotMatch(chunks.join(""), /\u001B\[\?25l/);
      assert.doesNotMatch(chunks.join(""), /\u001B\[[0-9]+F\u001B\[J/);
    });
  });

  it("falls back to numbered input when the terminal cannot enter raw mode", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    Object.assign(input, { isTTY: true });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: () => "● Personal\n○ Team\n",
      renderFallback: (activeIndex) => [
        `${activeIndex === 1 ? "1 ●" : "1 ○"} Personal`,
        `${activeIndex === 2 ? "2 ●" : "2 ○"} Team`,
        "",
      ].join("\n"),
      fallbackPrompt: "Choose an organization [1]: ",
    });
    input.write("2\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /1 ● Personal\n2 ○ Team/);
    assert.match(written, /Choose an organization \[1\]: /);
  });

  itWithAnsiTerminal("accepts numeric input before Enter and repaints the chosen option", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" },
        { value: "shared" }
      ],
      initialIndex: 1,
      render: (activeIndex) => [
        activeIndex === 1 ? "● Personal" : "○ Personal",
        activeIndex === 2 ? "● Team" : "○ Team",
        activeIndex === 3 ? "● Shared" : "○ Shared",
        "",
      ].join("\n")
    });
    input.write("2");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(stripAnsi(chunks.join("")), /○ Personal\n● Team\n○ Shared/);
  });

  itWithAnsiTerminal("shows an error for invalid numeric input and does not fall back to the previous highlight", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: (activeIndex) => activeIndex === 1 ? "● Personal\n○ Team\n" : "○ Personal\n● Team\n"
    });
    input.write("22");
    input.write("\n");
    input.write("\n");
    input.write("2");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    assert.deepEqual(rawModeTransitions, [true, false]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /Enter a number between 1 and 2\./);
    assert.match(written, /○ Personal\n● Team/);
  });

  itWithAnsiTerminal("uses arrow keys to choose an option without a numeric prompt", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: (activeIndex) => activeIndex === 1 ? "● Personal\n○ Team\n" : "○ Personal\n● Team\n"
    });
    input.write("\u001B[B");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(chunks.join(""), /● Personal/);
    assert.match(chunks.join(""), /● Team/);
    assert.doesNotMatch(chunks.join(""), /Choose an organization/);
  });

  itWithAnsiTerminal("buffers split arrow-key escape sequences across raw input chunks", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: (activeIndex) => activeIndex === 1 ? "● Personal\n○ Team\n" : "○ Personal\n● Team\n"
    });
    input.write("\u001B");
    input.write("[");
    input.write("B");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "team");
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(stripAnsi(chunks.join("")), /○ Personal\n● Team/);
  });

  itWithAnsiTerminal("repaints wrapped single-select frames using visual row counts on narrow terminals", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true, columns: 10 });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "first" },
        { value: "second" }
      ],
      initialIndex: 1,
      render: (activeIndex) => [
        activeIndex === 1 ? "● First option wraps twice" : "○ First option wraps twice",
        activeIndex === 2 ? "● Second choice wraps too" : "○ Second choice wraps too",
        "",
      ].join("\n")
    });
    input.write("\u001B[B");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "second");
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(chunks.join(""), /\u001B\[6F\u001B\[J/);
  });

  itWithAnsiTerminal("supports j and k navigation", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const output = new Writable({
      write(_chunk, _encoding, callback) {
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectChoice({
      options: [
        { value: "personal" },
        { value: "team" }
      ],
      initialIndex: 1,
      render: (activeIndex) => activeIndex === 1 ? "● Personal\n○ Team\n" : "○ Personal\n● Team\n"
    });
    input.write("j");
    input.write("k");
    input.write("\n");
    const selection = await selectionPromise;

    assert.equal(selection, "personal");
    assert.deepEqual(rawModeTransitions, [true, false]);
  });
});

describe("ReadlineDeployPrompts.selectManyChoices", () => {
  it("reads numeric input through readline when output is redirected", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    Object.assign(input, { isTTY: true });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: false });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: () => "› ○ Telegram\n  ○ Discord\n  ● Skip for now\n",
      renderFallback: (_activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `1  ${selected.has(1) ? "●" : "○"} Telegram`,
          `2  ${selected.has(2) ? "●" : "○"} Discord`,
          `3  ${selected.has(3) ? "●" : "○"} Skip for now`,
          "",
        ].join("\n");
      },
      fallbackPrompt: "Choose platform numbers [3]: ",
    });
    input.write("1,2\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram", "discord"]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /1  ○ Telegram\n2  ○ Discord\n3  ● Skip for now/);
    assert.match(written, /Choose platform numbers \[3\]: /);
  });

  it("falls back to numbered multiselect input on dumb terminals even when raw mode is available", async () => {
    await withMockedEnvVar("TERM", "dumb", async () => {
      const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
      const rawModeTransitions: boolean[] = [];
      Object.assign(input, {
        isTTY: true,
        setRawMode: (value: boolean) => {
          rawModeTransitions.push(value);
        }
      });

      const chunks: string[] = [];
      const output = new Writable({
        write(chunk, _encoding, callback) {
          chunks.push(chunk.toString());
          callback();
        }
      }) as Writable & NodeJS.WriteStream;
      Object.assign(output, { isTTY: true });

      const prompts = new ReadlineDeployPrompts(input, output);
      const selectionPromise = prompts.selectManyChoices({
        options: [
          { value: "telegram" },
          { value: "discord" },
          { value: "skip" }
        ],
        initialIndex: 3,
        initialSelectedIndices: [3],
        normalizeSelectedIndices: (selectedIndices, activeIndex) => (
          activeIndex === 3
            ? (selectedIndices.includes(3) ? [3] : [])
            : selectedIndices.filter((index) => index !== 3)
        ),
        render: () => "› ○ Telegram\n  ○ Discord\n  ● Skip for now\n",
        renderFallback: (_activeIndex, selectedIndices) => {
          const selected = new Set(selectedIndices);
          return [
            `1  ${selected.has(1) ? "●" : "○"} Telegram`,
            `2  ${selected.has(2) ? "●" : "○"} Discord`,
            `3  ${selected.has(3) ? "●" : "○"} Skip for now`,
            "",
          ].join("\n");
        },
        fallbackPrompt: "Choose platform numbers [3]: ",
      });
      input.write("1,2\n");
      const selection = await selectionPromise;

      assert.deepEqual(selection, ["telegram", "discord"]);
      const written = stripAnsi(chunks.join(""));
      assert.match(written, /1  ○ Telegram\n2  ○ Discord\n3  ● Skip for now/);
      assert.match(written, /Choose platform numbers \[3\]: /);
      assert.doesNotMatch(chunks.join(""), /\u001B\[\?25l/);
      assert.doesNotMatch(chunks.join(""), /\u001B\[[0-9]+F\u001B\[J/);
    });
  });

  it("falls back to numbered multiselect input when the terminal cannot enter raw mode", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    Object.assign(input, { isTTY: true });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: () => "› ○ Telegram\n  ○ Discord\n  ● Skip for now\n",
      renderFallback: (_activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `1  ${selected.has(1) ? "●" : "○"} Telegram`,
          `2  ${selected.has(2) ? "●" : "○"} Discord`,
          `3  ${selected.has(3) ? "●" : "○"} Skip for now`,
          "",
        ].join("\n");
      },
      fallbackPrompt: "Choose platform numbers [3]: ",
    });
    input.write("1, 2\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram", "discord"]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /1  ○ Telegram\n2  ○ Discord\n3  ● Skip for now/);
    assert.match(written, /Choose platform numbers \[3\]: /);
  });

  itWithAnsiTerminal("accepts comma-separated numeric input before Enter and repaints the chosen selections", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: (activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `${activeIndex === 1 ? "›" : " "} ${selected.has(1) ? "●" : "○"} Telegram`,
          `${activeIndex === 2 ? "›" : " "} ${selected.has(2) ? "●" : "○"} Discord`,
          `${activeIndex === 3 ? "›" : " "} ${selected.has(3) ? "●" : "○"} Skip for now`,
          "",
        ].join("\n");
      }
    });
    input.write("1, 2");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram", "discord"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(stripAnsi(chunks.join("")), /› ● Discord\n  ○ Skip for now/);
  });

  itWithAnsiTerminal("shows validation feedback for invalid numeric selections before accepting corrected input", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      validateSelectedIndices: (selectedIndices) => (
        selectedIndices.includes(3) && selectedIndices.length > 1
          ? "Choose either specific platforms or 3 to skip."
          : undefined
      ),
      render: (_activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `○ Telegram ${selected.has(1) ? "selected" : ""}`.trimEnd(),
          `○ Discord ${selected.has(2) ? "selected" : ""}`.trimEnd(),
          `○ Skip for now ${selected.has(3) ? "selected" : ""}`.trimEnd(),
          "",
        ].join("\n");
      }
    });
    input.write("1, 3");
    input.write("\n");
    input.write("1, 2");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram", "discord"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(stripAnsi(chunks.join("")), /Choose either specific platforms or 3 to skip\./);
  });

  itWithAnsiTerminal("shows an error for out-of-range numeric input and does not fall back to the existing selections", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: (activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `${activeIndex === 1 ? "›" : " "} ${selected.has(1) ? "●" : "○"} Telegram`,
          `${activeIndex === 2 ? "›" : " "} ${selected.has(2) ? "●" : "○"} Discord`,
          `${activeIndex === 3 ? "›" : " "} ${selected.has(3) ? "●" : "○"} Skip for now`,
          "",
        ].join("\n");
      }
    });
    input.write("1,9");
    input.write("\n");
    input.write("\n");
    input.write("1, 2");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram", "discord"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /Enter one or more numbers from 1 to 3, separated by commas\./);
    assert.match(written, /› ● Discord\n  ○ Skip for now/);
  });

  itWithAnsiTerminal("uses arrow keys and space to toggle selections before confirming", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: (activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        const lines = [
          [1, "Telegram"],
          [2, "Discord"],
          [3, "Skip for now"],
        ].map(([index, label]) => `${index === activeIndex ? "›" : " "} ${selected.has(index as number) ? "●" : "○"} ${label}`);
        return `${lines.join("\n")}\n`;
      }
    });
    input.write("\u001B[A");
    input.write("\u001B[A");
    input.write(" ");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["telegram"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /› ○ Telegram/);
    assert.match(written, /› ● Telegram/);
    assert.match(written, /○ Skip for now/);
  });

  itWithAnsiTerminal("buffers split arrow-key escape sequences in multiselect mode", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: (activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `${activeIndex === 1 ? "›" : " "} ${selected.has(1) ? "●" : "○"} Telegram`,
          `${activeIndex === 2 ? "›" : " "} ${selected.has(2) ? "●" : "○"} Discord`,
          `${activeIndex === 3 ? "›" : " "} ${selected.has(3) ? "●" : "○"} Skip for now`,
          "",
        ].join("\n");
      }
    });
    input.write("\u001B");
    input.write("[");
    input.write("A");
    input.write(" ");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["discord"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    const written = stripAnsi(chunks.join(""));
    assert.match(written, /› ○ Discord/);
    assert.match(written, /› ● Discord/);
  });

  itWithAnsiTerminal("repaints wrapped multiselect frames using visual row counts on narrow terminals", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const chunks: string[] = [];
    const output = new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true, columns: 10 });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "first" },
        { value: "second" }
      ],
      initialIndex: 1,
      initialSelectedIndices: [1],
      render: (activeIndex, selectedIndices) => {
        const selected = new Set(selectedIndices);
        return [
          `${activeIndex === 1 ? "›" : " "} ${selected.has(1) ? "●" : "○"} First option wraps twice`,
          `${activeIndex === 2 ? "›" : " "} ${selected.has(2) ? "●" : "○"} Second choice wraps too`,
          "",
        ].join("\n");
      }
    });
    input.write("\u001B[B");
    input.write(" ");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["first", "second"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
    assert.match(chunks.join(""), /\u001B\[6F\u001B\[J/);
  });

  itWithAnsiTerminal("supports j and k navigation in multiselect mode while keeping skip exclusive", async () => {
    const input = new PassThrough() as PassThrough & NodeJS.ReadStream;
    const rawModeTransitions: boolean[] = [];
    Object.assign(input, {
      isTTY: true,
      setRawMode: (value: boolean) => {
        rawModeTransitions.push(value);
      }
    });

    const output = new Writable({
      write(_chunk, _encoding, callback) {
        callback();
      }
    }) as Writable & NodeJS.WriteStream;
    Object.assign(output, { isTTY: true });

    const prompts = new ReadlineDeployPrompts(input, output);
    const selectionPromise = prompts.selectManyChoices({
      options: [
        { value: "telegram" },
        { value: "discord" },
        { value: "skip" }
      ],
      initialIndex: 3,
      initialSelectedIndices: [3],
      normalizeSelectedIndices: (selectedIndices, activeIndex) => (
        activeIndex === 3
          ? (selectedIndices.includes(3) ? [3] : [])
          : selectedIndices.filter((index) => index !== 3)
      ),
      render: (_activeIndex, _selectedIndices) => ""
    });
    input.write("k");
    input.write(" ");
    input.write("j");
    input.write("j");
    input.write(" ");
    input.write("\n");
    const selection = await selectionPromise;

    assert.deepEqual(selection, ["skip"]);
    assert.deepEqual(rawModeTransitions, [true, false]);
  });
});

describe("FlyDeployWizard.saveApp - persistence contract", () => {
  it("saveApp writes current_app and apps region entry", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp({
        ...DEFAULT_CONFIG,
        appName: "my-app",
        region: "iad",
        botToken: "123:abc",
        telegramBotUsername: "testhermesbot",
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappAllowedUsers: "393406844897",
        whatsappSessionConfirmed: true,
      });
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.ok(content.includes("current_app:"), `current_app: not found in:\n${content}`);
      assert.ok(content.includes("apps:"), `apps: not found in:\n${content}`);
      assert.ok(content.includes("- name:"), `- name: not found in:\n${content}`);
      assert.ok(content.includes("region:"), `region: not found in:\n${content}`);
      assert.ok(content.includes("provider: openrouter"), `provider missing in:\n${content}`);
      assert.ok(content.includes("platform: telegram"), `platform missing in:\n${content}`);
      assert.ok(content.includes("telegram_bot_username: testhermesbot"), `telegram bot username missing in:\n${content}`);
      assert.ok(content.includes("whatsapp_mode: self-chat"), `whatsapp mode missing in:\n${content}`);
      assert.ok(content.includes("whatsapp_allowed_users: 393406844897"), `whatsapp users missing in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  it("saveApp rewrites existing app entry without duplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp({ ...DEFAULT_CONFIG, appName: "my-app", region: "iad" });
      await wizard.saveApp({ ...DEFAULT_CONFIG, appName: "my-app", region: "lax" });
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  it("saveApp does not persist WhatsApp ownership metadata before pairing is confirmed", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-whatsapp-pending-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp({
        ...DEFAULT_CONFIG,
        appName: "my-app",
        region: "iad",
        whatsappEnabled: true,
        whatsappMode: "self-chat",
        whatsappAllowedUsers: "393406844897",
      });
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.doesNotMatch(content, /whatsapp_mode:/);
      assert.doesNotMatch(content, /whatsapp_allowed_users:/);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("FlyDeployWizard.saveApp - trailing lines preservation", () => {
  it("saveApp preserves non-target lines after apps section", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-trail-"));
    try {
      const { writeFile } = await import("node:fs/promises");
      const seed = [
        "current_app: old-app",
        "apps:",
        "  - name: old-app",
        "    region: ord",
        "metadata: keep-me",
      ].join("\n") + "\n";
      await writeFile(join(dir, "config.yaml"), seed, "utf8");

      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp({ ...DEFAULT_CONFIG, appName: "my-app", region: "iad" });
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.ok(content.includes("metadata: keep-me"), `metadata lost:\n${content}`);
      assert.ok(content.includes("current_app: my-app"), `current_app wrong:\n${content}`);
      assert.ok(content.includes("  - name: my-app"), `name entry missing:\n${content}`);
      assert.ok(content.includes("    region: iad"), `region missing:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("FlyDeployWizard.saveApp - whitespace-normalized dedup", () => {
  it("saveApp dedupes app entries with whitespace-normalized names", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-ws-"));
    try {
      const { writeFile } = await import("node:fs/promises");
      const seed = [
        "current_app: my-app",
        "apps:",
        "  - name: my-app   ",
        "    region: ord",
      ].join("\n") + "\n";
      await writeFile(join(dir, "config.yaml"), seed, "utf8");

      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp({ ...DEFAULT_CONFIG, appName: "my-app", region: "lax" });
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});
