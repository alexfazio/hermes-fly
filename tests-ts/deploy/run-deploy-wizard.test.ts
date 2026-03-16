import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PassThrough, Writable } from "node:stream";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { RunDeployWizardUseCase } from "../../src/contexts/deploy/application/use-cases/run-deploy-wizard.ts";
import type { DeployConfig, DeployWizardPort } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";
import { ReadlineDeployPrompts } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";
import { FlyDeployWizard } from "../../src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts";
import type { DeployPromptPort } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";
import type { QrCodeRendererPort } from "../../src/contexts/deploy/infrastructure/adapters/qr-code.ts";

function makeIO() {
  const lines: string[] = [];
  return {
    stderr: { write: (s: string) => { lines.push(s); } },
    get text() { return lines.join(""); }
  };
}

const DEFAULT_CONFIG: DeployConfig = {
  appName: "test-app",
  region: "iad",
  vmSize: "shared-cpu-1x",
  volumeSize: 5,
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
    ...overrides
  };
}

function makeProcessRunner(
  impl: (
    command: string,
    args: string[],
    options?: { cwd?: string; env?: NodeJS.ProcessEnv }
  ) => Promise<{ stdout?: string; stderr?: string; exitCode: number }>,
  foregroundImpl: (command: string, args: string[]) => Promise<{ exitCode: number }> = async () => ({ exitCode: 0 })
): ForegroundProcessRunner {
  return {
    run: async (command, args, options) => {
      const result = await impl(command, args, options);
      return {
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? "",
        exitCode: result.exitCode
      };
    },
    runStreaming: async () => ({ exitCode: 0 }),
    runForeground: async (command, args) => foregroundImpl(command, args)
  };
}

function makePromptPort(
  answers: string[],
  opts: { interactive?: boolean } = {}
): DeployPromptPort & { asked: string[]; secretAsked: string[]; pauses: string[]; writes: string[] } {
  const asked: string[] = [];
  const secretAsked: string[] = [];
  const pauses: string[] = [];
  const writes: string[] = [];
  return {
    asked,
    secretAsked,
    pauses,
    writes,
    isInteractive: () => opts.interactive ?? true,
    write: (message: string) => { writes.push(message); },
    ask: async (message: string) => {
      asked.push(message);
      return answers.shift() ?? "";
    },
    askSecret: async (message: string) => {
      secretAsked.push(message);
      return answers.shift() ?? "";
    },
    pause: async (message: string) => {
      pauses.push(message);
    }
  };
}

function makeQrRenderer(output = "[[QR: https://t.me/BotFather]]"): QrCodeRendererPort {
  return {
    render: async () => output
  };
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

describe("RunDeployWizardUseCase - happy path", () => {
  it("returns ok when all phases pass", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort());
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "ok");
  });

  it("saves app after successful deploy", async () => {
    const saved: Array<{ appName: string; region: string }> = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      saveApp: async (appName, region) => { saved.push({ appName, region }); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(saved.length, 1);
    assert.equal(saved[0].appName, "test-app");
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
      runDeploy: async () => ({ ok: false, error: "deploy failed" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("saves app even when fly deploy fails (preserves resources)", async () => {
    const saved: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({ ok: false, error: "deploy failed" }),
      saveApp: async (appName) => { saved.push(appName); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(saved.length, 1, "app should be saved even on deploy failure");
  });

  it("outputs resume hint after deploy failure", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({ ok: false, error: "deploy failed" })
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.ok(io.text.includes("resume") || io.text.includes("hermes-fly resume"), `expected resume hint, got: ${io.text}`);
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

describe("FlyDeployWizard.collectConfig", () => {
  it("suggests a unique editable deployment name using username and uid", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "sk-live",
      "",
      "",
      ""
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

  it("uses guided menus and friendly copy in interactive mode", async () => {
    const prompts = makePromptPort([
      "my-app",
      "2",
      "2",
      "2",
      "3",
      "sk-live",
      "2",
      "1",
      "1",
      "123:abc",
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
    assert.equal(config.channel, "preview");
    assert.deepEqual(prompts.secretAsked, [
      "OpenRouter API key (required): ",
      "Telegram bot token (required): "
    ]);
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Hermes Agent Guided Setup/);
    assert.match(guidedCopy, /Each deployment needs a unique name on Fly\.io/);
    assert.match(guidedCopy, /Where are you \(or most of your users\) located/);
    assert.match(guidedCopy, /How powerful should your agent's server be/);
    assert.match(guidedCopy, /How much storage should your agent have/);
    assert.match(guidedCopy, /Get your OpenRouter API key at: https:\/\/openrouter\.ai\/settings\/keys/);
    assert.match(guidedCopy, /Which AI provider do you want to use through OpenRouter/);
    assert.match(guidedCopy, /Which OpenAI model should your agent use/);
    assert.match(guidedCopy, /Do you want to connect Telegram now/);
    assert.match(guidedCopy, /Open BotFather directly: https:\/\/t\.me\/BotFather/);
    assert.match(guidedCopy, /Scan this QR code with your phone to open the BotFather chat/);
    assert.match(guidedCopy, /\[\[QR: https:\/\/t\.me\/BotFather\]\]/);
    assert.match(guidedCopy, /Review your setup/);
  });

  it("fetches the full OpenRouter provider catalog and lets the user choose a specific model", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
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
    assert.match(guidedCopy, /Anthropic/);
    assert.match(guidedCopy, /OpenAI/);
    assert.match(guidedCopy, /Mistral/);
    assert.match(guidedCopy, /Which OpenAI model should your agent use/);
    assert.match(guidedCopy, /GPT-5 Mini/);
    assert.match(guidedCopy, /GPT-5\s+/);
    assert.match(guidedCopy, /GPT-5 Pro/);
    assert.match(guidedCopy, /GPT-4o/);
  });

  it("shows a direct BotFather link and renders a QR code when Telegram setup is selected", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
      "sk-live",
      "2",
      "5",
      "1",
      "123:abc",
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
    const wizard = new FlyDeployWizard({}, {
      prompts,
      process: runner,
      qrRenderer: makeQrRenderer("[[BOTFATHER-QR]]")
    });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.botToken, "123:abc");
    const guidedCopy = prompts.writes.join("");
    assert.match(guidedCopy, /Open BotFather directly: https:\/\/t\.me\/BotFather/);
    assert.match(guidedCopy, /Scan this QR code with your phone to open the BotFather chat/);
    assert.match(guidedCopy, /\[\[BOTFATHER-QR\]\]/);
    assert.match(guidedCopy, /Guide: https:\/\/core\.telegram\.org\/bots#6-botfather/);
  });

  it("prompts for Hermes-compatible reasoning effort when the selected model supports it", async () => {
    const prompts = makePromptPort([
      "",
      "",
      "",
      "",
      "",
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
    assert.match(guidedCopy, /Which Anthropic model should your agent use/);
  });

  it("fails in non-interactive mode when OPENROUTER_API_KEY is missing", async () => {
    const prompts = makePromptPort([], { interactive: false });
    const wizard = new FlyDeployWizard({}, { prompts });

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

describe("FlyDeployWizard.saveApp - persistence contract", () => {
  it("saveApp writes current_app and apps region entry", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "iad");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.ok(content.includes("current_app:"), `current_app: not found in:\n${content}`);
      assert.ok(content.includes("apps:"), `apps: not found in:\n${content}`);
      assert.ok(content.includes("- name:"), `- name: not found in:\n${content}`);
      assert.ok(content.includes("region:"), `region: not found in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  it("saveApp rewrites existing app entry without duplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "iad");
      await wizard.saveApp("my-app", "lax");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
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
      await wizard.saveApp("my-app", "iad");
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
      await wizard.saveApp("my-app", "lax");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});
