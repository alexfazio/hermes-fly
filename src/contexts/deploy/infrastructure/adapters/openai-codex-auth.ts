import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { ProcessRunner } from "../../../../adapters/process.js";
import type { DeployPromptPort } from "./deploy-prompts.js";

const CODEX_DEVICE_AUTH_URL = "https://auth.openai.com/codex/device";
const CODEX_DEVICE_CODE_URL = "https://auth.openai.com/api/accounts/deviceauth/usercode";
const CODEX_DEVICE_TOKEN_URL = "https://auth.openai.com/api/accounts/deviceauth/token";
const CODEX_OAUTH_TOKEN_URL = "https://auth.openai.com/oauth/token";
const CODEX_MODELS_URL = "https://chatgpt.com/backend-api/codex/models?client_version=1.0.0";
const CODEX_OAUTH_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const CODEX_PROVIDER_ID = "openai-codex";
const AUTH_STORE_VERSION = 1;
const DEFAULT_CODEX_MODELS = [
  "gpt-5.3-codex",
  "gpt-5.2-codex",
  "gpt-5.1-codex-max",
  "gpt-5.1-codex-mini",
] as const;

type CodexTokens = {
  access_token: string;
  refresh_token: string;
};

type CodexProviderState = {
  tokens: CodexTokens;
  last_refresh: string;
  auth_mode: "chatgpt";
};

type HermesAuthStore = {
  version: number;
  providers: Record<string, unknown>;
  active_provider: string | null;
};

export type CodexAuthSource = "hermes" | "codex-cli" | "device-code";

export interface ResolvedCodexAuth {
  source: CodexAuthSource;
  accessToken: string;
  authJsonB64: string;
}

export interface CodexModelOption {
  value: string;
  label: string;
  bestFor: string;
  providerKey: string;
  providerLabel: string;
  supportsReasoning: boolean;
}

export class OpenAICodexAuthAdapter {
  constructor(
    private readonly process: ProcessRunner,
    private readonly env: NodeJS.ProcessEnv = globalThis.process.env,
    private readonly sleep: (ms: number) => Promise<void> = async (ms: number) => {
      await new Promise((resolve) => setTimeout(resolve, ms));
    }
  ) {}

  async resolveStoredAuth(): Promise<ResolvedCodexAuth | null> {
    const hermesAuth = await this.readHermesAuthStore();
    if (hermesAuth) {
      return {
        source: "hermes",
        accessToken: hermesAuth.tokens.access_token,
        authJsonB64: this.encodeAuthStore(this.buildAuthStore(hermesAuth.tokens, hermesAuth.last_refresh)),
      };
    }

    const codexCliTokens = await this.readCodexCliTokens();
    if (codexCliTokens) {
      const lastRefresh = this.nowIso();
      return {
        source: "codex-cli",
        accessToken: codexCliTokens.access_token,
        authJsonB64: this.encodeAuthStore(this.buildAuthStore(codexCliTokens, lastRefresh)),
      };
    }

    return null;
  }

  async runDeviceCodeLogin(prompts: DeployPromptPort): Promise<ResolvedCodexAuth> {
    const deviceCodeResponse = await this.requestDeviceCode();
    const userCode = String(deviceCodeResponse.user_code ?? "").trim();
    const deviceAuthId = String(deviceCodeResponse.device_auth_id ?? "").trim();
    const intervalSeconds = Math.max(3, Number(deviceCodeResponse.interval ?? 5) || 5);
    if (userCode.length === 0 || deviceAuthId.length === 0) {
      throw new Error("OpenAI Codex device login did not return the fields Hermes needs.");
    }

    prompts.write("Hermes can use your ChatGPT subscription through OpenAI Codex.\n");
    prompts.write("No API key is required for this path.\n\n");
    prompts.write("To continue, follow these steps:\n\n");
    prompts.write("  1. Open this URL in your browser:\n");
    prompts.write(`     ${CODEX_DEVICE_AUTH_URL}\n\n`);
    prompts.write("  2. Enter this one-time code:\n");
    prompts.write(`     ${userCode}\n\n`);
    prompts.write("Waiting for sign-in...\n");

    const authCodeResponse = await this.pollForAuthorizationCode(deviceAuthId, userCode, intervalSeconds);
    const authorizationCode = String(authCodeResponse.authorization_code ?? "").trim();
    const codeVerifier = String(authCodeResponse.code_verifier ?? "").trim();
    if (authorizationCode.length === 0 || codeVerifier.length === 0) {
      throw new Error("OpenAI Codex sign-in completed, but the token exchange data was incomplete.");
    }

    const tokenResponse = await this.exchangeAuthorizationCode(authorizationCode, codeVerifier);
    const accessToken = String(tokenResponse.access_token ?? "").trim();
    const refreshToken = String(tokenResponse.refresh_token ?? "").trim();
    if (accessToken.length === 0 || refreshToken.length === 0) {
      throw new Error("OpenAI Codex sign-in completed, but the returned tokens were incomplete.");
    }

    const lastRefresh = this.nowIso();
    return {
      source: "device-code",
      accessToken,
      authJsonB64: this.encodeAuthStore(this.buildAuthStore({
        access_token: accessToken,
        refresh_token: refreshToken,
      }, lastRefresh)),
    };
  }

  async fetchModels(accessToken: string): Promise<CodexModelOption[]> {
    const result = await this.process.run(
      "curl",
      [
        "-fsSL",
        "--max-time",
        "10",
        CODEX_MODELS_URL,
        "-H",
        `Authorization: Bearer ${accessToken}`,
      ],
      { env: this.env }
    );

    if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
      return this.staticModelOptions();
    }

    try {
      const payload = JSON.parse(result.stdout) as { models?: Array<Record<string, unknown>> };
      const models = (payload.models ?? [])
        .map((entry) => {
          const slug = String(entry.slug ?? "").trim();
          if (slug.length === 0) {
            return null;
          }
          if (entry.supported_in_api === false) {
            return null;
          }
          const visibility = String(entry.visibility ?? "").trim().toLowerCase();
          if (visibility === "hide" || visibility === "hidden") {
            return null;
          }
          const priority = Number(entry.priority ?? Number.MAX_SAFE_INTEGER);
          return { slug, priority };
        })
        .filter((entry): entry is { slug: string; priority: number } => entry !== null)
        .sort((left, right) => left.priority - right.priority || left.slug.localeCompare(right.slug));

      const deduped = [...new Set(models.map((entry) => entry.slug))];
      if (deduped.length === 0) {
        return this.staticModelOptions();
      }

      return deduped.map((slug) => this.buildModelOption(slug));
    } catch {
      return this.staticModelOptions();
    }
  }

  private async readHermesAuthStore(): Promise<CodexProviderState | null> {
    const home = this.homeDir();
    if (!home) {
      return null;
    }

    try {
      const raw = await readFile(join(home, ".hermes", "auth.json"), "utf8");
      const parsed = JSON.parse(raw) as HermesAuthStore;
      const providers = parsed.providers;
      if (!providers || typeof providers !== "object") {
        return null;
      }
      const state = providers[CODEX_PROVIDER_ID];
      if (!state || typeof state !== "object") {
        return null;
      }
      const tokens = (state as { tokens?: unknown }).tokens;
      if (!tokens || typeof tokens !== "object") {
        return null;
      }
      const accessToken = String((tokens as { access_token?: unknown }).access_token ?? "").trim();
      const refreshToken = String((tokens as { refresh_token?: unknown }).refresh_token ?? "").trim();
      if (accessToken.length === 0 || refreshToken.length === 0) {
        return null;
      }
      const lastRefresh = String((state as { last_refresh?: unknown }).last_refresh ?? this.nowIso()).trim() || this.nowIso();
      return {
        tokens: {
          access_token: accessToken,
          refresh_token: refreshToken,
        },
        last_refresh: lastRefresh,
        auth_mode: "chatgpt",
      };
    } catch {
      return null;
    }
  }

  private async readCodexCliTokens(): Promise<CodexTokens | null> {
    const codexHome = this.env.CODEX_HOME?.trim() || (this.homeDir() ? join(this.homeDir()!, ".codex") : "");
    if (codexHome.length === 0) {
      return null;
    }

    try {
      const raw = await readFile(join(codexHome, "auth.json"), "utf8");
      const parsed = JSON.parse(raw) as { tokens?: unknown };
      const tokens = parsed.tokens;
      if (!tokens || typeof tokens !== "object") {
        return null;
      }
      const accessToken = String((tokens as { access_token?: unknown }).access_token ?? "").trim();
      const refreshToken = String((tokens as { refresh_token?: unknown }).refresh_token ?? "").trim();
      if (accessToken.length === 0 || refreshToken.length === 0) {
        return null;
      }
      return {
        access_token: accessToken,
        refresh_token: refreshToken,
      };
    } catch {
      return null;
    }
  }

  private async requestDeviceCode(): Promise<Record<string, unknown>> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      CODEX_DEVICE_CODE_URL,
      "-H",
      "Content-Type: application/json",
      "-d",
      JSON.stringify({ client_id: CODEX_OAUTH_CLIENT_ID }),
    ]);

    if (payload.statusCode !== 200) {
      throw new Error(`OpenAI Codex device login failed to start (status ${payload.statusCode}).`);
    }
    return payload.body;
  }

  private async pollForAuthorizationCode(
    deviceAuthId: string,
    userCode: string,
    intervalSeconds: number
  ): Promise<Record<string, unknown>> {
    const deadline = Date.now() + 15 * 60 * 1000;

    while (Date.now() < deadline) {
      await this.sleep(intervalSeconds * 1000);
      const payload = await this.runJsonRequestWithStatus([
        "-sS",
        "--max-time",
        "15",
        "-X",
        "POST",
        CODEX_DEVICE_TOKEN_URL,
        "-H",
        "Content-Type: application/json",
        "-d",
        JSON.stringify({
          device_auth_id: deviceAuthId,
          user_code: userCode,
        }),
      ]);

      if (payload.statusCode === 200) {
        return payload.body;
      }
      if (payload.statusCode === 403 || payload.statusCode === 404) {
        continue;
      }
      throw new Error(`OpenAI Codex sign-in returned status ${payload.statusCode} while waiting for approval.`);
    }

    throw new Error("OpenAI Codex sign-in timed out after 15 minutes.");
  }

  private async exchangeAuthorizationCode(
    authorizationCode: string,
    codeVerifier: string
  ): Promise<Record<string, unknown>> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      CODEX_OAUTH_TOKEN_URL,
      "-H",
      "Content-Type: application/x-www-form-urlencoded",
      "--data-urlencode",
      "grant_type=authorization_code",
      "--data-urlencode",
      `code=${authorizationCode}`,
      "--data-urlencode",
      "redirect_uri=https://auth.openai.com/deviceauth/callback",
      "--data-urlencode",
      `client_id=${CODEX_OAUTH_CLIENT_ID}`,
      "--data-urlencode",
      `code_verifier=${codeVerifier}`,
    ]);

    if (payload.statusCode !== 200) {
      throw new Error(`OpenAI Codex token exchange failed (status ${payload.statusCode}).`);
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
          return {
            statusCode: 200,
            body: JSON.parse(output) as Record<string, unknown>,
          };
        } catch {
          throw new Error("OpenAI Codex request did not return an HTTP status code.");
        }
      }
      throw new Error("OpenAI Codex request did not return an HTTP status code.");
    }

    if (bodyText.trim().length === 0) {
      return { statusCode, body: {} };
    }

    try {
      return {
        statusCode,
        body: JSON.parse(bodyText) as Record<string, unknown>,
      };
    } catch {
      throw new Error("OpenAI Codex returned malformed JSON.");
    }
  }

  private buildAuthStore(tokens: CodexTokens, lastRefresh: string): HermesAuthStore {
    return {
      version: AUTH_STORE_VERSION,
      providers: {
        [CODEX_PROVIDER_ID]: {
          tokens,
          last_refresh: lastRefresh,
          auth_mode: "chatgpt",
        },
      },
      active_provider: CODEX_PROVIDER_ID,
    };
  }

  private encodeAuthStore(authStore: HermesAuthStore): string {
    return Buffer.from(JSON.stringify(authStore, null, 2), "utf8").toString("base64");
  }

  private staticModelOptions(): CodexModelOption[] {
    return [...DEFAULT_CODEX_MODELS].map((slug) => this.buildModelOption(slug));
  }

  private buildModelOption(slug: string): CodexModelOption {
    const normalized = slug.trim();
    return {
      value: normalized,
      label: this.labelForModel(normalized),
      bestFor: this.noteForModel(normalized),
      providerKey: "openai",
      providerLabel: "OpenAI",
      supportsReasoning: false,
    };
  }

  private labelForModel(slug: string): string {
    return slug
      .split("-")
      .map((part, index) => {
        if (index === 0 && part.toLowerCase() === "gpt") {
          return "GPT";
        }
        if (/^[0-9.]+$/.test(part)) {
          return part;
        }
        return part.charAt(0).toUpperCase() + part.slice(1);
      })
      .join(" ");
  }

  private noteForModel(slug: string): string {
    const haystack = slug.toLowerCase();
    if (haystack.includes("mini") || haystack.includes("spark")) {
      return "Fast / lower cost";
    }
    if (haystack.includes("max") || haystack.includes("pro")) {
      return "Higher capability";
    }
    return "OpenAI Codex model";
  }

  private nowIso(): string {
    return new Date().toISOString().replace(".000Z", "Z");
  }

  private homeDir(): string | undefined {
    return this.env.HOME?.trim() || process.env.HOME;
  }
}
