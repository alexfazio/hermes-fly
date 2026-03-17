import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { OpenAICodexAuthAdapter } from "../../src/contexts/deploy/infrastructure/adapters/openai-codex-auth.ts";
import type { DeployPromptPort } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";

function makeProcessRunner(
  impl: (
    command: string,
    args: string[],
    options?: { cwd?: string; env?: NodeJS.ProcessEnv }
  ) => Promise<{ stdout?: string; stderr?: string; exitCode: number }>
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
    runForeground: async () => ({ exitCode: 0 })
  };
}

function makePromptPort(
  answers: string[] = []
): DeployPromptPort & { writes: string[]; asked: string[] } {
  const writes: string[] = [];
  const asked: string[] = [];
  return {
    writes,
    asked,
    isInteractive: () => true,
    write: (message: string) => { writes.push(message); },
    ask: async (message: string) => {
      asked.push(message);
      return answers.shift() ?? "";
    },
    askSecret: async (message: string) => {
      asked.push(message);
      return answers.shift() ?? "";
    },
    pause: async () => {}
  };
}

describe("OpenAICodexAuthAdapter", () => {
  it("reuses a Hermes auth store when openai-codex credentials already exist", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-codex-home-"));
    const hermesDir = join(home, ".hermes");
    await mkdir(hermesDir, { recursive: true });
    await writeFile(join(hermesDir, "auth.json"), JSON.stringify({
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

    try {
      const adapter = new OpenAICodexAuthAdapter(
        makeProcessRunner(async () => ({ exitCode: 1 })),
        { HOME: home }
      );

      const result = await adapter.resolveStoredAuth();

      assert.ok(result);
      assert.equal(result?.source, "hermes");
      assert.equal(result?.accessToken, "access-hermes");
      const decoded = JSON.parse(Buffer.from(result?.authJsonB64 ?? "", "base64").toString("utf8"));
      assert.equal(decoded.active_provider, "openai-codex");
      assert.equal(decoded.providers["openai-codex"].tokens.refresh_token, "refresh-hermes");
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("imports Codex CLI auth into Hermes auth-store format when Hermes auth is absent", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-codex-cli-"));
    const codexDir = join(home, ".codex");
    await mkdir(codexDir, { recursive: true });
    await writeFile(join(codexDir, "auth.json"), JSON.stringify({
      tokens: {
        access_token: "access-codex",
        refresh_token: "refresh-codex"
      }
    }), "utf8");

    try {
      const adapter = new OpenAICodexAuthAdapter(
        makeProcessRunner(async () => ({ exitCode: 1 })),
        { HOME: home, CODEX_HOME: codexDir }
      );

      const result = await adapter.resolveStoredAuth();

      assert.ok(result);
      assert.equal(result?.source, "codex-cli");
      const decoded = JSON.parse(Buffer.from(result?.authJsonB64 ?? "", "base64").toString("utf8"));
      assert.equal(decoded.active_provider, "openai-codex");
      assert.equal(decoded.providers["openai-codex"].tokens.access_token, "access-codex");
      assert.equal(decoded.providers["openai-codex"].auth_mode, "chatgpt");
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("runs the device-code login flow and returns a Hermes auth-store payload", async () => {
    const prompts = makePromptPort();
    const adapter = new OpenAICodexAuthAdapter(
      makeProcessRunner(async (command, args) => {
        assert.equal(command, "curl");
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
        throw new Error(`Unexpected curl call: ${args.join(" ")}`);
      }),
      {},
      async () => {}
    );

    const result = await adapter.runDeviceCodeLogin(prompts);

    assert.equal(result.source, "device-code");
    assert.equal(result.accessToken, "access-device");
    const decoded = JSON.parse(Buffer.from(result.authJsonB64, "base64").toString("utf8"));
    assert.equal(decoded.providers["openai-codex"].tokens.refresh_token, "refresh-device");
    const copy = prompts.writes.join("");
    assert.match(copy, /https:\/\/auth\.openai\.com\/codex\/device/);
    assert.match(copy, /ABCD-EFGH/);
    assert.match(copy, /Waiting for sign-in/);
  });

  it("fetches live Codex models and falls back to defaults when the live catalog is unavailable", async () => {
    let fetchCount = 0;
    const adapter = new OpenAICodexAuthAdapter(
      makeProcessRunner(async (command, args) => {
        assert.equal(command, "curl");
        fetchCount += 1;
        if (fetchCount === 1) {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              models: [
                { slug: "gpt-5.3-codex", priority: 2 },
                { slug: "gpt-5.4", priority: 1 },
                { slug: "hidden-model", priority: 3, visibility: "hidden" }
              ]
            })
          };
        }
        return { exitCode: 28, stderr: "timed out" };
      })
    );

    const liveModels = await adapter.fetchModels("access-token");
    const fallbackModels = await adapter.fetchModels("access-token");

    assert.deepEqual(
      liveModels.map((option) => option.value),
      ["gpt-5.4", "gpt-5.3-codex"]
    );
    assert.deepEqual(
      fallbackModels.map((option) => option.value),
      ["gpt-5.3-codex", "gpt-5.2-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini"]
    );
  });
});
