import { createHash, randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { ProcessRunner } from "../../../../adapters/process.js";
import type { DeployPromptPort } from "./deploy-prompts.js";

const ANTHROPIC_OAUTH_AUTHORIZE_URL = "https://claude.ai/oauth/authorize";
const ANTHROPIC_OAUTH_TOKEN_URL = "https://console.anthropic.com/v1/oauth/token";
const ANTHROPIC_OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const ANTHROPIC_OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
const ANTHROPIC_OAUTH_SCOPE = "org:create_api_key user:profile user:inference";
const ANTHROPIC_CLAUDE_CODE_USER_AGENT = "claude-cli/2.1.74 (external, cli)";

const DEFAULT_ANTHROPIC_MODELS = [
  "claude-sonnet-4-6",
  "claude-opus-4-6",
  "claude-sonnet-4-5-20250929",
  "claude-haiku-4-5-20251001",
] as const;

type StoredAnthropicOauth = {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
};

export type AnthropicAuthSource = "hermes" | "claude-code" | "oauth";

export interface ResolvedAnthropicAuth {
  source: AnthropicAuthSource;
  accessToken: string;
  oauthJsonB64: string;
}

export interface AnthropicModelOption {
  value: string;
  label: string;
  bestFor: string;
  providerKey: string;
  providerLabel: string;
  supportsReasoning: boolean;
}

export class AnthropicAuthAdapter {
  constructor(
    private readonly process: ProcessRunner,
    private readonly env: NodeJS.ProcessEnv = globalThis.process.env,
    private readonly generateVerifier: () => string = () => encodeBase64Url(randomBytes(32))
  ) {}

  async resolveStoredAuth(): Promise<ResolvedAnthropicAuth | null> {
    const hermes = await this.readHermesOauth();
    if (hermes) {
      return {
        source: "hermes",
        accessToken: hermes.accessToken,
        oauthJsonB64: this.encodeOauthJson(hermes),
      };
    }

    const claudeCode = await this.readClaudeCodeCredentials();
    if (claudeCode) {
      return {
        source: "claude-code",
        accessToken: claudeCode.accessToken,
        oauthJsonB64: this.encodeOauthJson(claudeCode),
      };
    }

    return null;
  }

  async runOauthLogin(prompts: DeployPromptPort): Promise<ResolvedAnthropicAuth> {
    const verifier = this.generateVerifier();
    const challenge = sha256Base64Url(verifier);
    const authUrl = this.buildAuthorizationUrl(challenge, verifier);

    prompts.write("Hermes can use your Claude / Anthropic subscription through OAuth.\n");
    prompts.write("No separate API key is required for this path.\n\n");
    prompts.write("To continue, follow these steps:\n\n");
    prompts.write("  1. Open this URL in your browser:\n");
    prompts.write(`     ${authUrl}\n\n`);
    prompts.write("  2. Approve access, then copy the authorization code shown by Anthropic.\n");
    prompts.write("     If Anthropic shows code#state, paste the full value below.\n\n");

    const rawAuthorizationCode = (await prompts.ask("Authorization code: ")).trim();
    if (rawAuthorizationCode.length === 0) {
      throw new Error("Anthropic OAuth did not receive an authorization code.");
    }

    const [code, state = ""] = rawAuthorizationCode.split("#", 2);
    const tokenPayload = await this.exchangeAuthorizationCode(code, state, verifier);
    const accessToken = String(tokenPayload.access_token ?? "").trim();
    const refreshToken = String(tokenPayload.refresh_token ?? "").trim();
    const expiresIn = Math.max(60, Number(tokenPayload.expires_in ?? 3600) || 3600);
    if (accessToken.length === 0) {
      throw new Error("Anthropic OAuth completed, but no access token was returned.");
    }

    const oauth = {
      accessToken,
      refreshToken: refreshToken.length > 0 ? refreshToken : undefined,
      expiresAt: Date.now() + expiresIn * 1000,
    };
    return {
      source: "oauth",
      accessToken,
      oauthJsonB64: this.encodeOauthJson(oauth),
    };
  }

  staticModelOptions(): AnthropicModelOption[] {
    return [...DEFAULT_ANTHROPIC_MODELS].map((modelId) => this.buildModelOption(modelId));
  }

  private buildAuthorizationUrl(challenge: string, verifier: string): string {
    const params = new URLSearchParams({
      code: "true",
      client_id: ANTHROPIC_OAUTH_CLIENT_ID,
      response_type: "code",
      redirect_uri: ANTHROPIC_OAUTH_REDIRECT_URI,
      scope: ANTHROPIC_OAUTH_SCOPE,
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: verifier,
    });
    return `${ANTHROPIC_OAUTH_AUTHORIZE_URL}?${params.toString()}`;
  }

  private async exchangeAuthorizationCode(
    code: string,
    state: string,
    verifier: string
  ): Promise<Record<string, unknown>> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      ANTHROPIC_OAUTH_TOKEN_URL,
      "-H",
      "Content-Type: application/json",
      "-H",
      `User-Agent: ${ANTHROPIC_CLAUDE_CODE_USER_AGENT}`,
      "-d",
      JSON.stringify({
        grant_type: "authorization_code",
        client_id: ANTHROPIC_OAUTH_CLIENT_ID,
        code,
        state,
        redirect_uri: ANTHROPIC_OAUTH_REDIRECT_URI,
        code_verifier: verifier,
      }),
    ]);

    if (payload.statusCode !== 200) {
      throw new Error(`Anthropic OAuth token exchange failed (status ${payload.statusCode}).`);
    }
    return payload.body;
  }

  private async runJsonRequestWithStatus(args: string[]): Promise<{ statusCode: number; body: Record<string, unknown> }> {
    const result = await this.process.run(
      "curl",
      [...args, "-w", "\\n%{http_code}"],
      { env: this.env }
    );

    const output = result.stdout.trimEnd();
    const newlineIndex = output.lastIndexOf("\n");
    const statusText = newlineIndex === -1 ? output : output.slice(newlineIndex + 1);
    const bodyText = newlineIndex === -1 ? "" : output.slice(0, newlineIndex);
    const statusCode = Number(statusText.trim());
    if (!Number.isInteger(statusCode)) {
      if (result.exitCode === 0) {
        try {
          return { statusCode: 200, body: JSON.parse(output) as Record<string, unknown> };
        } catch {
          throw new Error("Anthropic OAuth request did not return an HTTP status code.");
        }
      }
      throw new Error("Anthropic OAuth request did not return an HTTP status code.");
    }

    if (bodyText.trim().length === 0) {
      return { statusCode, body: {} };
    }

    try {
      return { statusCode, body: JSON.parse(bodyText) as Record<string, unknown> };
    } catch {
      throw new Error("Anthropic OAuth returned malformed JSON.");
    }
  }

  private async readHermesOauth(): Promise<StoredAnthropicOauth | null> {
    const home = this.homeDir();
    if (!home) {
      return null;
    }

    try {
      const raw = await readFile(join(home, ".hermes", ".anthropic_oauth.json"), "utf8");
      return normalizeOauthJson(JSON.parse(raw) as Record<string, unknown>);
    } catch {
      return null;
    }
  }

  private async readClaudeCodeCredentials(): Promise<StoredAnthropicOauth | null> {
    const home = this.homeDir();
    if (!home) {
      return null;
    }

    try {
      const raw = await readFile(join(home, ".claude", ".credentials.json"), "utf8");
      const parsed = JSON.parse(raw) as { claudeAiOauth?: Record<string, unknown> };
      return normalizeOauthJson(parsed.claudeAiOauth ?? {});
    } catch {
      return null;
    }
  }

  private encodeOauthJson(oauth: StoredAnthropicOauth): string {
    return Buffer.from(JSON.stringify({
      accessToken: oauth.accessToken,
      refreshToken: oauth.refreshToken ?? "",
      expiresAt: oauth.expiresAt ?? 0,
    }, null, 2), "utf8").toString("base64");
  }

  private buildModelOption(modelId: string): AnthropicModelOption {
    const normalized = modelId.trim();
    return {
      value: normalized,
      label: labelForAnthropicModel(normalized),
      bestFor: noteForAnthropicModel(normalized),
      providerKey: "anthropic",
      providerLabel: "Anthropic",
      supportsReasoning: supportsReasoning(normalized),
    };
  }

  private homeDir(): string | null {
    const home = this.env.HOME?.trim();
    return home && home.length > 0 ? home : null;
  }
}

function normalizeOauthJson(raw: Record<string, unknown>): StoredAnthropicOauth | null {
  const accessToken = String(raw.accessToken ?? "").trim();
  if (accessToken.length === 0) {
    return null;
  }
  const refreshToken = String(raw.refreshToken ?? "").trim();
  const expiresAt = Number(raw.expiresAt ?? 0);
  return {
    accessToken,
    refreshToken: refreshToken.length > 0 ? refreshToken : undefined,
    expiresAt: Number.isFinite(expiresAt) && expiresAt > 0 ? expiresAt : undefined,
  };
}

function supportsReasoning(modelId: string): boolean {
  return /^claude-(?:sonnet|opus)-4-6(?:[-.].+)?$/i.test(modelId.trim());
}

function labelForAnthropicModel(modelId: string): string {
  switch (modelId) {
    case "claude-sonnet-4-6":
      return "Claude Sonnet 4.6";
    case "claude-opus-4-6":
      return "Claude Opus 4.6";
    case "claude-sonnet-4-5-20250929":
      return "Claude Sonnet 4.5";
    case "claude-haiku-4-5-20251001":
      return "Claude Haiku 4.5";
    default:
      return modelId.replace(/[-_]/g, " ");
  }
}

function noteForAnthropicModel(modelId: string): string {
  if (/haiku/i.test(modelId)) {
    return "Fast / lower cost";
  }
  if (/opus|sonnet-4-6/i.test(modelId)) {
    return "Higher capability";
  }
  return "Anthropic model";
}

function sha256Base64Url(value: string): string {
  return createHash("sha256").update(value).digest("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function encodeBase64Url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}
