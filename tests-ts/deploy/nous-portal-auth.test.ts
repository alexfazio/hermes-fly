import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { NousPortalAuthAdapter } from "../../src/contexts/deploy/infrastructure/adapters/nous-portal-auth.ts";
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

function makePromptPort(): DeployPromptPort & { writes: string[] } {
  const writes: string[] = [];
  return {
    writes,
    isInteractive: () => true,
    write: (message: string) => {
      writes.push(message);
    },
    ask: async () => "",
    askSecret: async () => "",
    pause: async () => {},
  };
}

describe("NousPortalAuthAdapter", () => {
  it("reuses a Hermes auth store when nous credentials already exist", async () => {
    const home = await mkdtemp(join(tmpdir(), "hermes-nous-home-"));
    const hermesDir = join(home, ".hermes");
    await mkdir(hermesDir, { recursive: true });
    await writeFile(
      join(hermesDir, "auth.json"),
      JSON.stringify({
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
            agent_key_obtained_at: null,
          },
        },
        active_provider: "nous",
      }),
      "utf8"
    );

    try {
      const adapter = new NousPortalAuthAdapter(
        makeProcessRunner(async () => ({ exitCode: 1 })),
        { HOME: home }
      );

      const result = await adapter.resolveStoredAuth();

      assert.ok(result);
      assert.equal(result?.source, "hermes");
      assert.equal(result?.accessToken, "access-nous");
      assert.equal(result?.portalBaseUrl, "https://portal.nousresearch.com");
      assert.equal(result?.inferenceBaseUrl, "https://inference-api.nousresearch.com/v1");
      const decoded = JSON.parse(Buffer.from(result?.authJsonB64 ?? "", "base64").toString("utf8"));
      assert.equal(decoded.active_provider, "nous");
      assert.equal(decoded.providers.nous.refresh_token, "refresh-nous");
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  it("runs the Nous Portal device-code login flow and returns a Hermes auth-store payload", async () => {
    const prompts = makePromptPort();
    const adapter = new NousPortalAuthAdapter(
      makeProcessRunner(async (command, args) => {
        assert.equal(command, "curl");
        const target = args.find((value) => value.startsWith("https://"));
        if (target === "https://portal.nousresearch.com/api/oauth/device/code") {
          return {
            exitCode: 0,
            stdout: `${JSON.stringify({
              device_code: "device-code-123",
              user_code: "WXYZ-1234",
              verification_uri: "https://portal.nousresearch.com/device",
              verification_uri_complete: "https://portal.nousresearch.com/device?code=WXYZ-1234",
              expires_in: 900,
              interval: 0,
            })}\n200`,
          };
        }
        if (target === "https://portal.nousresearch.com/api/oauth/token") {
          return {
            exitCode: 0,
            stdout: `${JSON.stringify({
              access_token: "access-device",
              refresh_token: "refresh-device",
              token_type: "Bearer",
              scope: "inference:mint_agent_key",
              expires_in: 3600,
              inference_base_url: "https://inference-api.nousresearch.com/v1",
            })}\n200`,
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
    assert.equal(decoded.active_provider, "nous");
    assert.equal(decoded.providers.nous.refresh_token, "refresh-device");
    const copy = prompts.writes.join("");
    assert.match(copy, /https:\/\/portal\.nousresearch\.com\/device\?code=WXYZ-1234/);
    assert.match(copy, /WXYZ-1234/);
    assert.match(copy, /Waiting for sign-in/);
  });

  it("mints a Portal agent key and fetches live models", async () => {
    const authStoreB64 = Buffer.from(JSON.stringify({
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
          agent_key_obtained_at: null,
        },
      },
      active_provider: "nous",
    }), "utf8").toString("base64");

    const adapter = new NousPortalAuthAdapter(
      makeProcessRunner(async (command, args) => {
        assert.equal(command, "curl");
        const target = args.find((value) => value.startsWith("https://"));
        if (target === "https://portal.nousresearch.com/api/oauth/agent-key") {
          return {
            exitCode: 0,
            stdout: `${JSON.stringify({
              api_key: "agent-key-123",
              inference_base_url: "https://inference-api.nousresearch.com/v1",
            })}\n200`,
          };
        }
        if (target === "https://inference-api.nousresearch.com/v1/models") {
          return {
            exitCode: 0,
            stdout: JSON.stringify({
              data: [
                { id: "gpt-5.4" },
                { id: "nous-hermes-3" },
                { id: "gpt-5.4-mini" },
              ],
            }),
          };
        }
        throw new Error(`Unexpected curl call: ${args.join(" ")}`);
      })
    );

    const result = await adapter.fetchModels({
      source: "hermes",
      accessToken: "access-nous",
      authJsonB64: authStoreB64,
      portalBaseUrl: "https://portal.nousresearch.com",
      inferenceBaseUrl: "https://inference-api.nousresearch.com/v1",
    });

    assert.deepEqual(
      result.map((option) => option.value),
      ["gpt-5.4", "gpt-5.4-mini"]
    );
    assert.equal(result[0]?.supportsReasoning, true);
    assert.equal(result[1]?.supportsReasoning, true);
  });
});
