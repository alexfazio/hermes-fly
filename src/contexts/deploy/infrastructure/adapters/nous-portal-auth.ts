import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { ProcessRunner } from "../../../../adapters/process.js";
import type { DeployPromptPort } from "./deploy-prompts.js";

const DEFAULT_NOUS_PORTAL_URL = "https://portal.nousresearch.com";
const DEFAULT_NOUS_INFERENCE_URL = "https://inference-api.nousresearch.com/v1";
const DEFAULT_NOUS_CLIENT_ID = "hermes-cli";
const DEFAULT_NOUS_SCOPE = "inference:mint_agent_key";
const AUTH_STORE_VERSION = 1;

type HermesAuthStore = {
  version: number;
  providers: Record<string, unknown>;
  active_provider: string | null;
};

type NousProviderState = {
  portal_base_url: string;
  inference_base_url: string;
  client_id: string;
  scope: string;
  token_type: string;
  access_token: string;
  refresh_token?: string;
  obtained_at: string;
  expires_at: string;
  expires_in: number;
  tls: {
    insecure: boolean;
    ca_bundle: string | null;
  };
  agent_key: string | null;
  agent_key_id: string | null;
  agent_key_expires_at: string | null;
  agent_key_expires_in: number | null;
  agent_key_reused: boolean | null;
  agent_key_obtained_at: string | null;
};

export type NousPortalAuthSource = "hermes" | "device-code";

export interface ResolvedNousPortalAuth {
  source: NousPortalAuthSource;
  accessToken: string;
  authJsonB64: string;
  portalBaseUrl: string;
  inferenceBaseUrl: string;
}

export interface NousModelOption {
  value: string;
  label: string;
  bestFor: string;
  providerKey: string;
  providerLabel: string;
  supportsReasoning: boolean;
}

export class NousPortalAuthAdapter {
  constructor(
    private readonly process: ProcessRunner,
    private readonly env: NodeJS.ProcessEnv = globalThis.process.env,
    private readonly sleep: (ms: number) => Promise<void> = async (ms: number) => {
      await new Promise((resolve) => setTimeout(resolve, ms));
    }
  ) {}

  async resolveStoredAuth(): Promise<ResolvedNousPortalAuth | null> {
    const state = await this.readHermesAuthStore();
    if (!state) {
      return null;
    }

    return {
      source: "hermes",
      accessToken: state.access_token,
      authJsonB64: this.encodeAuthStore(this.buildAuthStore(state)),
      portalBaseUrl: state.portal_base_url,
      inferenceBaseUrl: state.inference_base_url,
    };
  }

  async runDeviceCodeLogin(prompts: DeployPromptPort): Promise<ResolvedNousPortalAuth> {
    const portalBaseUrl = this.portalBaseUrl();
    const requestedInferenceBaseUrl = this.inferenceBaseUrl();
    const clientId = DEFAULT_NOUS_CLIENT_ID;
    const scope = DEFAULT_NOUS_SCOPE;

    const deviceCodeResponse = await this.requestDeviceCode(portalBaseUrl, clientId, scope);
    const deviceCode = String(deviceCodeResponse.device_code ?? "").trim();
    const userCode = String(deviceCodeResponse.user_code ?? "").trim();
    const verificationUriComplete = String(deviceCodeResponse.verification_uri_complete ?? "").trim();
    const verificationUri = String(deviceCodeResponse.verification_uri ?? "").trim();
    const expiresIn = Math.max(1, Number(deviceCodeResponse.expires_in ?? 900) || 900);
    const intervalSeconds = Math.max(1, Number(deviceCodeResponse.interval ?? 5) || 5);
    if (deviceCode.length === 0 || userCode.length === 0) {
      throw new Error("Nous Portal device login did not return the fields Hermes needs.");
    }

    const verificationUrl = verificationUriComplete || verificationUri;
    if (verificationUrl.length === 0) {
      throw new Error("Nous Portal device login did not return a verification URL.");
    }

    prompts.write("Hermes can use your Nous Portal subscription.\n");
    prompts.write("No separate API key is required for this path.\n\n");
    prompts.write("To continue, follow these steps:\n\n");
    prompts.write("  1. Open this URL in your browser:\n");
    prompts.write(`     ${verificationUrl}\n\n`);
    prompts.write("  2. If prompted, enter this one-time code:\n");
    prompts.write(`     ${userCode}\n\n`);
    prompts.write("Waiting for sign-in...\n");

    const tokenResponse = await this.pollForToken(
      portalBaseUrl,
      clientId,
      deviceCode,
      expiresIn,
      intervalSeconds
    );

    const accessToken = String(tokenResponse.access_token ?? "").trim();
    const refreshToken = String(tokenResponse.refresh_token ?? "").trim();
    const tokenType = String(tokenResponse.token_type ?? "Bearer").trim() || "Bearer";
    const resolvedScope = String(tokenResponse.scope ?? scope).trim() || scope;
    const tokenExpiresIn = Math.max(60, Number(tokenResponse.expires_in ?? 3600) || 3600);
    if (accessToken.length === 0) {
      throw new Error("Nous Portal sign-in completed, but no access token was returned.");
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + tokenExpiresIn * 1000).toISOString();
    const inferenceBaseUrl = String(tokenResponse.inference_base_url ?? requestedInferenceBaseUrl).trim()
      || requestedInferenceBaseUrl;

    const providerState: NousProviderState = {
      portal_base_url: portalBaseUrl,
      inference_base_url: inferenceBaseUrl,
      client_id: clientId,
      scope: resolvedScope,
      token_type: tokenType,
      access_token: accessToken,
      refresh_token: refreshToken || undefined,
      obtained_at: now.toISOString(),
      expires_at: expiresAt,
      expires_in: tokenExpiresIn,
      tls: {
        insecure: false,
        ca_bundle: null,
      },
      agent_key: null,
      agent_key_id: null,
      agent_key_expires_at: null,
      agent_key_expires_in: null,
      agent_key_reused: null,
      agent_key_obtained_at: null,
    };

    return {
      source: "device-code",
      accessToken,
      authJsonB64: this.encodeAuthStore(this.buildAuthStore(providerState)),
      portalBaseUrl,
      inferenceBaseUrl,
    };
  }

  async fetchModels(auth: ResolvedNousPortalAuth): Promise<NousModelOption[]> {
    const state = this.decodeAuthState(auth.authJsonB64);
    const minted = await this.mintAgentKey(
      state.portal_base_url,
      state.client_id || DEFAULT_NOUS_CLIENT_ID,
      state.access_token,
      state.refresh_token
    );
    const inferenceBaseUrl = minted.inferenceBaseUrl || state.inference_base_url || auth.inferenceBaseUrl;
    const result = await this.process.run(
      "curl",
      [
        "-fsSL",
        "--max-time",
        "15",
        `${inferenceBaseUrl.replace(/\/+$/, "")}/models`,
        "-H",
        `Authorization: Bearer ${minted.apiKey}`,
      ],
      { env: this.env }
    );

    if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
      return [];
    }

    try {
      const payload = JSON.parse(result.stdout) as { data?: Array<Record<string, unknown>> };
      const ids = [...new Set((payload.data ?? [])
        .map((entry) => String(entry.id ?? "").trim())
        .filter((id) => id.length > 0)
        .filter((id) => !id.toLowerCase().includes("hermes")))];
      ids.sort((left, right) => this.modelPriority(left) - this.modelPriority(right) || left.localeCompare(right));
      return ids.map((id) => this.buildModelOption(id));
    } catch {
      return [];
    }
  }

  private async readHermesAuthStore(): Promise<NousProviderState | null> {
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
      const state = providers.nous;
      if (!state || typeof state !== "object") {
        return null;
      }
      return this.normalizeState(state as Record<string, unknown>);
    } catch {
      return null;
    }
  }

  private normalizeState(state: Record<string, unknown>): NousProviderState | null {
    const accessToken = String(state.access_token ?? "").trim();
    if (accessToken.length === 0) {
      return null;
    }

    return {
      portal_base_url: String(state.portal_base_url ?? this.portalBaseUrl()).trim() || this.portalBaseUrl(),
      inference_base_url: String(state.inference_base_url ?? this.inferenceBaseUrl()).trim() || this.inferenceBaseUrl(),
      client_id: String(state.client_id ?? DEFAULT_NOUS_CLIENT_ID).trim() || DEFAULT_NOUS_CLIENT_ID,
      scope: String(state.scope ?? DEFAULT_NOUS_SCOPE).trim() || DEFAULT_NOUS_SCOPE,
      token_type: String(state.token_type ?? "Bearer").trim() || "Bearer",
      access_token: accessToken,
      refresh_token: String(state.refresh_token ?? "").trim() || undefined,
      obtained_at: String(state.obtained_at ?? new Date().toISOString()).trim() || new Date().toISOString(),
      expires_at: String(state.expires_at ?? "").trim() || new Date().toISOString(),
      expires_in: Math.max(60, Number(state.expires_in ?? 3600) || 3600),
      tls: {
        insecure: Boolean((state.tls as { insecure?: unknown } | undefined)?.insecure ?? false),
        ca_bundle: ((state.tls as { ca_bundle?: unknown } | undefined)?.ca_bundle ?? null) as string | null,
      },
      agent_key: asOptionalString(state.agent_key),
      agent_key_id: asOptionalString(state.agent_key_id),
      agent_key_expires_at: asOptionalString(state.agent_key_expires_at),
      agent_key_expires_in: asOptionalNumber(state.agent_key_expires_in),
      agent_key_reused: typeof state.agent_key_reused === "boolean" ? state.agent_key_reused : null,
      agent_key_obtained_at: asOptionalString(state.agent_key_obtained_at),
    };
  }

  private async requestDeviceCode(
    portalBaseUrl: string,
    clientId: string,
    scope: string
  ): Promise<Record<string, unknown>> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      `${portalBaseUrl}/api/oauth/device/code`,
      "--data-urlencode",
      `client_id=${clientId}`,
      "--data-urlencode",
      `scope=${scope}`,
    ]);

    if (payload.statusCode !== 200) {
      throw new Error(`Nous Portal device login failed to start (status ${payload.statusCode}).`);
    }
    return payload.body;
  }

  private async pollForToken(
    portalBaseUrl: string,
    clientId: string,
    deviceCode: string,
    expiresInSeconds: number,
    intervalSeconds: number
  ): Promise<Record<string, unknown>> {
    const deadline = Date.now() + expiresInSeconds * 1000;

    while (Date.now() < deadline) {
      await this.sleep(intervalSeconds * 1000);
      const payload = await this.runJsonRequestWithStatus([
        "-sS",
        "--max-time",
        "15",
        "-X",
        "POST",
        `${portalBaseUrl}/api/oauth/token`,
        "--data-urlencode",
        "grant_type=urn:ietf:params:oauth:grant-type:device_code",
        "--data-urlencode",
        `client_id=${clientId}`,
        "--data-urlencode",
        `device_code=${deviceCode}`,
      ]);

      if (payload.statusCode === 200) {
        return payload.body;
      }

      const errorCode = String(payload.body.error ?? "").trim();
      if (
        errorCode === "authorization_pending"
        || errorCode === "slow_down"
        || payload.statusCode === 400
      ) {
        continue;
      }

      throw new Error(`Nous Portal sign-in returned status ${payload.statusCode} while waiting for approval.`);
    }

    throw new Error("Nous Portal sign-in timed out after waiting for approval.");
  }

  private async mintAgentKey(
    portalBaseUrl: string,
    clientId: string,
    accessToken: string,
    refreshToken?: string
  ): Promise<{ apiKey: string; inferenceBaseUrl: string }> {
    const firstAttempt = await this.runMintAgentKey(portalBaseUrl, accessToken);
    if (firstAttempt.ok) {
      return firstAttempt.value;
    }

    if ((firstAttempt.code === "invalid_token" || firstAttempt.code === "invalid_grant") && refreshToken) {
      const refreshed = await this.refreshAccessToken(portalBaseUrl, clientId, refreshToken);
      const secondAttempt = await this.runMintAgentKey(portalBaseUrl, refreshed.accessToken);
      if (secondAttempt.ok) {
        return secondAttempt.value;
      }
    }

    throw new Error(firstAttempt.error ?? "Nous Portal could not mint an inference API key.");
  }

  private async runMintAgentKey(
    portalBaseUrl: string,
    accessToken: string
  ): Promise<{ ok: true; value: { apiKey: string; inferenceBaseUrl: string } } | { ok: false; error?: string; code?: string }> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      `${portalBaseUrl}/api/oauth/agent-key`,
      "-H",
      "Content-Type: application/json",
      "-H",
      `Authorization: Bearer ${accessToken}`,
      "-d",
      JSON.stringify({ min_ttl_seconds: 300 }),
    ]);

    if (payload.statusCode === 200) {
      const apiKey = String(payload.body.api_key ?? "").trim();
      if (apiKey.length === 0) {
        return { ok: false, error: "Nous Portal mint response did not include an API key." };
      }
      return {
        ok: true,
        value: {
          apiKey,
          inferenceBaseUrl: String(payload.body.inference_base_url ?? this.inferenceBaseUrl()).trim() || this.inferenceBaseUrl(),
        }
      };
    }

    return {
      ok: false,
      error: String(payload.body.error_description ?? payload.body.error ?? `Agent key mint failed with status ${payload.statusCode}`).trim(),
      code: String(payload.body.error ?? "").trim() || undefined,
    };
  }

  private async refreshAccessToken(
    portalBaseUrl: string,
    clientId: string,
    refreshToken: string
  ): Promise<{ accessToken: string }> {
    const payload = await this.runJsonRequestWithStatus([
      "-sS",
      "--max-time",
      "15",
      "-X",
      "POST",
      `${portalBaseUrl}/api/oauth/token`,
      "--data-urlencode",
      "grant_type=refresh_token",
      "--data-urlencode",
      `client_id=${clientId}`,
      "--data-urlencode",
      `refresh_token=${refreshToken}`,
    ]);

    if (payload.statusCode !== 200) {
      throw new Error("Nous Portal access token refresh failed.");
    }

    const accessToken = String(payload.body.access_token ?? "").trim();
    if (accessToken.length === 0) {
      throw new Error("Nous Portal refresh response did not include an access token.");
    }
    return { accessToken };
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
          throw new Error("Nous Portal request did not return an HTTP status code.");
        }
      }
      throw new Error("Nous Portal request did not return an HTTP status code.");
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
      throw new Error("Nous Portal returned malformed JSON.");
    }
  }

  private buildAuthStore(state: NousProviderState): HermesAuthStore {
    return {
      version: AUTH_STORE_VERSION,
      providers: {
        nous: state,
      },
      active_provider: "nous",
    };
  }

  private decodeAuthState(authJsonB64: string): NousProviderState {
    try {
      const raw = Buffer.from(authJsonB64, "base64").toString("utf8");
      const parsed = JSON.parse(raw) as HermesAuthStore;
      const state = parsed.providers?.nous;
      if (state && typeof state === "object") {
        const normalized = this.normalizeState(state as Record<string, unknown>);
        if (normalized) {
          return normalized;
        }
      }
    } catch {
      // handled below
    }

    throw new Error("HERMES_AUTH_JSON_B64 does not contain valid Nous Portal credentials.");
  }

  private encodeAuthStore(authStore: HermesAuthStore): string {
    return Buffer.from(JSON.stringify(authStore, null, 2), "utf8").toString("base64");
  }

  private buildModelOption(id: string): NousModelOption {
    return {
      value: id,
      label: this.labelForModel(id),
      bestFor: this.noteForModel(id),
      providerKey: "nous",
      providerLabel: "Nous",
      supportsReasoning: this.supportsReasoning(id),
    };
  }

  private supportsReasoning(id: string): boolean {
    return /^gpt-5(?:[.-].+)?$/i.test(id.trim());
  }

  private labelForModel(id: string): string {
    const tail = id.includes("/") ? id.split("/").pop() ?? id : id;
    return tail
      .split(/[-_]/)
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

  private noteForModel(id: string): string {
    const haystack = id.toLowerCase();
    if (haystack.includes("mini") || haystack.includes("flash")) {
      return "Fast / lower cost";
    }
    if (haystack.includes("max") || haystack.includes("pro") || haystack.includes("opus")) {
      return "Higher capability";
    }
    return "Nous Portal model";
  }

  private modelPriority(id: string): number {
    const haystack = id.toLowerCase();
    if (haystack.includes("opus")) {
      return 0;
    }
    if (haystack.includes("pro")) {
      return 1;
    }
    if (haystack.includes("sonnet")) {
      return 3;
    }
    return 2;
  }

  private portalBaseUrl(): string {
    const value = this.env.HERMES_PORTAL_BASE_URL?.trim()
      || this.env.NOUS_PORTAL_BASE_URL?.trim()
      || DEFAULT_NOUS_PORTAL_URL;
    return value.replace(/\/+$/, "");
  }

  private inferenceBaseUrl(): string {
    const value = this.env.NOUS_INFERENCE_BASE_URL?.trim() || DEFAULT_NOUS_INFERENCE_URL;
    return value.replace(/\/+$/, "");
  }

  private homeDir(): string | undefined {
    const home = this.env.HOME?.trim();
    return home && home.length > 0 ? home : undefined;
  }
}

function asOptionalString(value: unknown): string | null {
  const normalized = String(value ?? "").trim();
  return normalized.length > 0 ? normalized : null;
}

function asOptionalNumber(value: unknown): number | null {
  const normalized = Number(value);
  return Number.isFinite(normalized) ? normalized : null;
}
