import type { ProcessRunner } from "../../../../adapters/process.js";

const DEFAULT_ZAI_CODING_BASE_URL = "https://api.z.ai/api/coding/paas/v4";
const DEFAULT_ZAI_GENERAL_BASE_URL = "https://api.z.ai/api/paas/v4";

const ZAI_ENDPOINTS = [
  {
    id: "coding-global",
    baseUrl: DEFAULT_ZAI_CODING_BASE_URL,
    defaultModel: "glm-4.7",
    label: "Global (Coding Plan)",
  },
  {
    id: "coding-cn",
    baseUrl: "https://open.bigmodel.cn/api/coding/paas/v4",
    defaultModel: "glm-4.7",
    label: "China (Coding Plan)",
  },
  {
    id: "global",
    baseUrl: DEFAULT_ZAI_GENERAL_BASE_URL,
    defaultModel: "glm-5",
    label: "Global",
  },
  {
    id: "cn",
    baseUrl: "https://open.bigmodel.cn/api/paas/v4",
    defaultModel: "glm-5",
    label: "China",
  },
] as const;

const DEFAULT_ZAI_MODELS = [
  "glm-5",
  "glm-4.7",
  "glm-4.5",
  "glm-4.5-flash",
] as const;

export interface ZaiEndpointResolution {
  id: string;
  baseUrl: string;
  defaultModel: string;
  label: string;
}

export interface ZaiModelOption {
  value: string;
  label: string;
  bestFor: string;
  providerKey: string;
  providerLabel: string;
  supportsReasoning: boolean;
}

export interface ZaiApiKeyValidation {
  ok: boolean;
  reason?: string;
  warning?: string;
}

interface ZaiEndpointProbeResult {
  statusCode: number | null;
}

export class ZaiApiKeyAdapter {
  constructor(
    private readonly process: ProcessRunner,
    private readonly env: NodeJS.ProcessEnv = globalThis.process.env
  ) {}

  resolvePresetApiKey(): string | null {
    const candidates = [
      this.env.GLM_API_KEY,
      this.env.ZAI_API_KEY,
      this.env.Z_AI_API_KEY,
    ];
    for (const candidate of candidates) {
      const value = String(candidate ?? "").trim();
      if (value.length > 0) {
        return value;
      }
    }
    return null;
  }

  resolvePresetBaseUrl(): string | null {
    const value = String(this.env.GLM_BASE_URL ?? "").trim();
    return value.length > 0 ? value : null;
  }

  async detectEndpoint(apiKey: string): Promise<ZaiEndpointResolution | null> {
    for (const endpoint of ZAI_ENDPOINTS) {
      const probe = await this.probeEndpoint(apiKey, endpoint);
      if (probe.statusCode === 200) {
        return { ...endpoint };
      }
    }

    return null;
  }

  async validateApiKey(apiKey: string, baseUrl?: string): Promise<ZaiApiKeyValidation> {
    const trimmed = apiKey.trim();
    const suspicious = explainPasteError(trimmed);
    if (suspicious) {
      return {
        ok: false,
        reason: suspicious,
      };
    }

    const configuredBaseUrl = String(baseUrl ?? "").trim();
    const endpoints = configuredBaseUrl.length > 0
      ? [endpointForBaseUrl(configuredBaseUrl)]
      : ZAI_ENDPOINTS.map((endpoint) => ({ ...endpoint }));

    const statuses: number[] = [];
    let sawReachabilityFailure = false;

    for (const endpoint of endpoints) {
      const probe = await this.probeEndpoint(trimmed, endpoint);
      if (probe.statusCode === 200) {
        return { ok: true };
      }
      if (probe.statusCode === null) {
        sawReachabilityFailure = true;
        continue;
      }
      statuses.push(probe.statusCode);
    }

    if (statuses.length === 0 && sawReachabilityFailure) {
      return {
        ok: true,
        warning: configuredBaseUrl.length > 0
          ? "I could not verify this Z.AI key against GLM_BASE_URL right now. Hermes will continue with the configured endpoint."
          : "I could not verify this Z.AI key right now. Hermes will continue and use the detected or default endpoint.",
      };
    }

    return {
      ok: false,
      reason: describeProbeFailure(statuses, configuredBaseUrl),
    };
  }

  staticModelOptions(preferredModel?: string): ZaiModelOption[] {
    const preferred = (preferredModel ?? "").trim();
    const ordered = [...DEFAULT_ZAI_MODELS].sort((left, right) => {
      if (left === preferred) {
        return -1;
      }
      if (right === preferred) {
        return 1;
      }
      return 0;
    });

    return ordered.map((modelId) => this.buildModelOption(modelId));
  }

  codingFallback(): ZaiEndpointResolution {
    return { ...ZAI_ENDPOINTS[0] };
  }

  private async probeEndpoint(apiKey: string, endpoint: ZaiEndpointResolution): Promise<ZaiEndpointProbeResult> {
    const result = await this.process.run(
      "curl",
      [
        "-sS",
        "--max-time",
        "8",
        "-o",
        "-",
        "-w",
        "\n%{http_code}",
        "-X",
        "POST",
        `${endpoint.baseUrl}/chat/completions`,
        "-H",
        `Authorization: Bearer ${apiKey}`,
        "-H",
        "Content-Type: application/json",
        "-d",
        JSON.stringify({
          model: endpoint.defaultModel,
          stream: false,
          max_tokens: 1,
          messages: [{ role: "user", content: "ping" }],
        }),
      ],
      { env: this.env }
    );

    if (result.exitCode !== 0) {
      return { statusCode: null };
    }

    return {
      statusCode: readStatusCode(result.stdout),
    };
  }

  private buildModelOption(modelId: string): ZaiModelOption {
    return {
      value: modelId,
      label: humanizeModel(modelId),
      bestFor: describeModel(modelId),
      providerKey: "zai",
      providerLabel: "Z.AI",
      supportsReasoning: false,
    };
  }
}

function readStatusCode(stdout: string): number | null {
  const trimmed = stdout.trim();
  if (trimmed.length === 0) {
    return null;
  }

  const lines = trimmed.split(/\r?\n/);
  const status = Number(lines[lines.length - 1]);
  return Number.isFinite(status) ? status : null;
}

function humanizeModel(modelId: string): string {
  return modelId
    .split("-")
    .map((part) => (/^\d/.test(part) ? part : part.toUpperCase()))
    .join(" ");
}

function describeModel(modelId: string): string {
  if (modelId === "glm-4.7") {
    return "Recommended for Coding Plan";
  }
  if (modelId === "glm-5") {
    return "Higher capability";
  }
  if (modelId.includes("flash")) {
    return "Fast / lower cost";
  }
  return "Z.AI model";
}

function endpointForBaseUrl(baseUrl: string): ZaiEndpointResolution {
  const normalized = baseUrl.replace(/\/+$/, "");
  const known = ZAI_ENDPOINTS.find((endpoint) => endpoint.baseUrl === normalized);
  if (known) {
    return { ...known };
  }
  return {
    id: "configured",
    baseUrl: normalized,
    defaultModel: normalized.includes("/coding/") ? "glm-4.7" : "glm-5",
    label: "Configured via GLM_BASE_URL",
  };
}

function explainPasteError(value: string): string | undefined {
  if (value.length === 0) {
    return "GLM_API_KEY cannot be empty.";
  }

  if (/[\\/]/.test(value) && /\.[A-Za-z0-9]{2,5}$/.test(value)) {
    return "This looks like a file path, not a Z.AI API key. Paste the actual GLM API key from your Z.AI account.";
  }

  if (/^https?:\/\//i.test(value)) {
    return "This looks like a URL, not a Z.AI API key. Paste the actual GLM API key from your Z.AI account.";
  }

  return undefined;
}

function describeProbeFailure(statuses: number[], configuredBaseUrl: string): string {
  if (statuses.includes(401) || statuses.includes(403)) {
    return "Z.AI rejected this key. Paste a valid GLM API key from your Z.AI account and try again.";
  }

  if (statuses.includes(402)) {
    return "Z.AI accepted the request but no usable GLM endpoint is available for this key right now. Check your GLM plan or billing, then try again.";
  }

  if (configuredBaseUrl.length > 0 && statuses.includes(404)) {
    return "GLM_BASE_URL did not point to a working Z.AI chat endpoint. Check GLM_BASE_URL and try again.";
  }

  return "I could reach Z.AI, but this key did not authorize a usable GLM endpoint. Check the key and your plan, then try again.";
}
