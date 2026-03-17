import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { AnthropicAuthAdapter } from "../../src/contexts/deploy/infrastructure/adapters/anthropic-auth.ts";
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
        exitCode: result.exitCode,
      };
    },
    runStreaming: async () => ({ exitCode: 0 }),
    runForeground: async () => ({ exitCode: 0 }),
  };
}

function makePromptPort(answers: string[] = []): DeployPromptPort & { writes: string[] } {
  const writes: string[] = [];
  return {
    writes,
    isInteractive: () => true,
    write: (message: string) => {
      writes.push(message);
    },
    ask: async () => answers.shift() ?? "",
    askSecret: async () => "",
    pause: async () => {},
  };
}

describe("AnthropicAuthAdapter", () => {
  it("reuses Hermes Anthropic OAuth credentials when already present", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-anthropic-home-"));
    const hermesDir = join(home, ".hermes");
    await mkdir(hermesDir, { recursive: true });
    await writeFile(
      join(hermesDir, ".anthropic_oauth.json"),
      JSON.stringify({
        accessToken: "access-hermes",
        refreshToken: "refresh-hermes",
        expiresAt: 1_900_000_000_000,
      }),
      "utf8"
    );

    try {
      const adapter = new AnthropicAuthAdapter(
        makeProcessRunner(async () => ({ exitCode: 1 })),
        { HOME: home }
      );

      const result = await adapter.resolveStoredAuth();

      assert.ok(result);
      assert.equal(result?.source, "hermes");
      assert.equal(result?.accessToken, "access-hermes");
      const decoded = JSON.parse(Buffer.from(result?.oauthJsonB64 ?? "", "base64").toString("utf8"));
      assert.equal(decoded.accessToken, "access-hermes");
      assert.equal(decoded.refreshToken, "refresh-hermes");
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("imports Claude Code credentials into the Hermes Anthropic OAuth format", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-anthropic-claude-"));
    const claudeDir = join(home, ".claude");
    await mkdir(claudeDir, { recursive: true });
    await writeFile(
      join(claudeDir, ".credentials.json"),
      JSON.stringify({
        claudeAiOauth: {
          accessToken: "access-claude",
          refreshToken: "refresh-claude",
          expiresAt: 1_900_000_000_000,
        }
      }),
      "utf8"
    );

    try {
      const adapter = new AnthropicAuthAdapter(
        makeProcessRunner(async () => ({ exitCode: 1 })),
        { HOME: home }
      );

      const result = await adapter.resolveStoredAuth();

      assert.ok(result);
      assert.equal(result?.source, "claude-code");
      assert.equal(result?.accessToken, "access-claude");
      const decoded = JSON.parse(Buffer.from(result?.oauthJsonB64 ?? "", "base64").toString("utf8"));
      assert.equal(decoded.accessToken, "access-claude");
      assert.equal(decoded.refreshToken, "refresh-claude");
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("runs the Anthropic PKCE OAuth flow and returns Hermes-compatible oauth bootstrap JSON", async () => {
    const prompts = makePromptPort(["auth-code-123#returned-state"]);
    const adapter = new AnthropicAuthAdapter(
      makeProcessRunner(async (command, args) => {
        assert.equal(command, "curl");
        const target = args.find((value) => value.startsWith("https://"));
        assert.equal(target, "https://console.anthropic.com/v1/oauth/token");
        return {
          exitCode: 0,
          stdout: `${JSON.stringify({
            access_token: "access-oauth",
            refresh_token: "refresh-oauth",
            expires_in: 3600,
          })}\n200`,
        };
      }),
      {},
      () => "verifier-123",
    );

    const result = await adapter.runOauthLogin(prompts);

    assert.equal(result.source, "oauth");
    assert.equal(result.accessToken, "access-oauth");
    const decoded = JSON.parse(Buffer.from(result.oauthJsonB64, "base64").toString("utf8"));
    assert.equal(decoded.accessToken, "access-oauth");
    assert.equal(decoded.refreshToken, "refresh-oauth");
    assert.match(prompts.writes.join(""), /https:\/\/claude\.ai\/oauth\/authorize\?/);
    assert.match(prompts.writes.join(""), /copy the authorization code shown by Anthropic/i);
  });

  it("offers verified Anthropic model choices and flags Claude 4.6 reasoning support", () => {
    const adapter = new AnthropicAuthAdapter(makeProcessRunner(async () => ({ exitCode: 1 })));

    const models = adapter.staticModelOptions();

    assert.deepEqual(models.map((model) => model.value), [
      "claude-sonnet-4-6",
      "claude-opus-4-6",
      "claude-sonnet-4-5-20250929",
      "claude-haiku-4-5-20251001",
    ]);
    assert.equal(models[0]?.supportsReasoning, true);
    assert.equal(models[1]?.supportsReasoning, true);
    assert.equal(models[2]?.supportsReasoning, false);
    assert.equal(models[3]?.supportsReasoning, false);
  });
});
