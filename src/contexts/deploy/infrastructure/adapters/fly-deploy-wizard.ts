import type { DeployConfig, DeployWizardPort } from "../../application/ports/deploy-wizard.port.js";
import { FlyDeployRunner } from "./fly-deploy-runner.js";
import { TemplateWriter } from "./template-writer.js";
import { NodeProcessRunner, type ForegroundProcessRunner } from "../../../../adapters/process.js";
import { DeploymentIntent } from "../../domain/deployment-intent.js";
import { ReadlineDeployPrompts, type DeployPromptPort } from "./deploy-prompts.js";
import { TerminalQrCodeRenderer, type QrCodeRendererPort } from "./qr-code.js";
import {
  OpenAICodexAuthAdapter,
  type CodexModelOption,
  type ResolvedCodexAuth,
} from "./openai-codex-auth.js";
import { MessagingPolicy, type MessagingPolicyMode } from "../../../messaging/domain/messaging-policy.js";
import { randomBytes } from "node:crypto";
import { constants } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const DEFAULT_APP_NAME_PREFIX = "hermes";
const DEFAULT_REGION = "iad";
const DEFAULT_VM_SIZE = "shared-cpu-1x";
const DEFAULT_VOLUME_SIZE = 1;
const DEFAULT_MODEL = "anthropic/claude-3-5-sonnet";
const DEFAULT_CHANNEL = "stable";
const SAFE_PROCESS_LOCALE = "C";
const OPENROUTER_KEY_URL = "https://openrouter.ai/settings/keys";
const OPENROUTER_MODELS_URL = "https://openrouter.ai/models";
const OPENROUTER_KEY_API_URL = "https://openrouter.ai/api/v1/key";
const OPENROUTER_MODELS_API_URL = "https://openrouter.ai/api/v1/models";
const TELEGRAM_BOTFATHER_URL = "https://t.me/BotFather";
const TELEGRAM_BOTFATHER_NEWBOT_URL = `${TELEGRAM_BOTFATHER_URL}?text=${encodeURIComponent("/newbot")}`;
const TELEGRAM_BOTFATHER_DELETEBOT_URL = `${TELEGRAM_BOTFATHER_URL}?text=${encodeURIComponent("/deletebot")}`;
const TELEGRAM_USERINFOBOT_URL = "https://t.me/userinfobot";

type RegionOption = {
  code: string;
  name: string;
  area: string;
};

type FlyOrgOption = {
  slug: string;
  name: string;
  type?: string;
};

type VmOption = {
  value: string;
  tier: string;
  ramLabel: string;
  costLabel: string;
  bestFor: string;
};

type VolumeOption = {
  value: number;
  costLabel: string;
  bestFor: string;
};

type ModelOption = {
  value: string;
  label: string;
  bestFor: string;
  providerKey: string;
  providerLabel: string;
  supportsReasoning: boolean;
};

type OpenRouterModelRecord = {
  id: string;
  name: string;
  supportedParameters: string[];
};

type ProviderOption = {
  key: string;
  label: string;
  description: string;
};

type ReasoningPolicy = {
  allowedEfforts: string[];
  defaultEffort: string;
};

type ReasoningSupport = {
  supported: boolean;
  allowedEfforts: string[];
  defaultEffort?: string;
  unsupportedMessage?: string;
};

type TelegramSetup = {
  botToken: string;
  botUsername?: string;
  botName?: string;
  allowedUsers?: string;
  allowAllUsers?: boolean;
  homeChannel?: string;
};

type TelegramBotIdentity = {
  username: string;
  firstName: string;
};

type AiAccessSelection = {
  provider: "openrouter" | "openai-codex";
  apiKey: string;
  authJsonB64?: string;
  model: string;
  reasoningEffort?: string;
};

const STATIC_REGIONS: RegionOption[] = [
  { code: "iad", name: "Ashburn, Virginia (US)", area: "Americas" },
  { code: "ord", name: "Chicago, Illinois (US)", area: "Americas" },
  { code: "dfw", name: "Dallas, Texas (US)", area: "Americas" },
  { code: "lax", name: "Los Angeles, California (US)", area: "Americas" },
  { code: "sjc", name: "San Jose, California (US)", area: "Americas" },
  { code: "ewr", name: "Secaucus, New Jersey (US)", area: "Americas" },
  { code: "yyz", name: "Toronto, Canada", area: "Americas" },
  { code: "ams", name: "Amsterdam, Netherlands", area: "Europe" },
  { code: "fra", name: "Frankfurt, Germany", area: "Europe" },
  { code: "lhr", name: "London, United Kingdom", area: "Europe" },
  { code: "cdg", name: "Paris, France", area: "Europe" },
  { code: "arn", name: "Stockholm, Sweden", area: "Europe" },
  { code: "bom", name: "Mumbai, India", area: "Asia-Pacific" },
  { code: "nrt", name: "Tokyo, Japan", area: "Asia-Pacific" },
  { code: "sin", name: "Singapore, Singapore", area: "Asia-Pacific" },
  { code: "syd", name: "Sydney, Australia", area: "Oceania" },
  { code: "gru", name: "Sao Paulo, Brazil", area: "South America" },
  { code: "jnb", name: "Johannesburg, South Africa", area: "Africa" },
];

const REGION_AREA_ORDER = ["Americas", "Europe", "Asia-Pacific", "Oceania", "South America", "Africa", "Other"];

const STATIC_VM_OPTIONS: VmOption[] = [
  {
    value: "shared-cpu-1x",
    tier: "Starter",
    ramLabel: "256 MB",
    costLabel: "~$2/mo",
    bestFor: "Trying it out. Lowest cost.",
  },
  {
    value: "shared-cpu-2x",
    tier: "Standard",
    ramLabel: "512 MB",
    costLabel: "~$4/mo",
    bestFor: "Most users. Better under everyday load.",
  },
  {
    value: "performance-1x",
    tier: "Pro",
    ramLabel: "2 GB",
    costLabel: "~$32/mo",
    bestFor: "Heavy use or larger agents.",
  },
  {
    value: "performance-2x",
    tier: "Power",
    ramLabel: "4 GB",
    costLabel: "~$64/mo",
    bestFor: "Sustained heavy workloads.",
  },
];

const STATIC_VOLUME_OPTIONS: VolumeOption[] = [
  { value: 1, costLabel: "~$0.15/mo", bestFor: "Light use and testing" },
  { value: 5, costLabel: "~$0.75/mo", bestFor: "Most users and everyday chats" },
  { value: 10, costLabel: "~$1.50/mo", bestFor: "Heavy use and more history" },
];

const STATIC_MODEL_OPTIONS: ModelOption[] = [
  {
    value: "anthropic/claude-3-5-sonnet",
    label: "Claude 3.5 Sonnet",
    bestFor: "Balanced and reliable",
    providerKey: "anthropic",
    providerLabel: "Anthropic",
    supportsReasoning: false,
  },
  {
    value: "anthropic/claude-3-5-haiku",
    label: "Claude 3.5 Haiku",
    bestFor: "Fast and lower cost",
    providerKey: "anthropic",
    providerLabel: "Anthropic",
    supportsReasoning: false,
  },
  {
    value: "openai/gpt-4.1-mini",
    label: "GPT-4.1 Mini",
    bestFor: "Good general-purpose fallback",
    providerKey: "openai",
    providerLabel: "OpenAI",
    supportsReasoning: false,
  },
  {
    value: "google/gemini-2.5-flash",
    label: "Gemini 2.5 Flash",
    bestFor: "Fast Google option",
    providerKey: "google",
    providerLabel: "Google",
    supportsReasoning: false,
  },
  {
    value: "meta-llama/llama-4-maverick",
    label: "Llama 4 Maverick",
    bestFor: "Open source option",
    providerKey: "meta-llama",
    providerLabel: "Meta",
    supportsReasoning: false,
  },
  {
    value: "mistralai/mistral-large",
    label: "Mistral Large",
    bestFor: "Strong multilingual fallback",
    providerKey: "mistralai",
    providerLabel: "Mistral",
    supportsReasoning: false,
  },
];

const PROVIDER_ORDER = ["anthropic", "openai", "google", "meta-llama", "mistralai"];
const HERMES_AGENT_DEFAULT_REF = "8eefbef91cd715cfe410bba8c13cfab4eb3040df";
const HERMES_AGENT_PREVIEW_REF = HERMES_AGENT_DEFAULT_REF;
const HERMES_AGENT_EDGE_REF = "main";
const STATIC_REASONING_POLICIES = new Map<string, ReasoningPolicy>([
  ["gpt-5", { allowedEfforts: ["low", "medium", "high"], defaultEffort: "medium" }],
  ["gpt-5-pro", { allowedEfforts: ["high"], defaultEffort: "high" }]
]);

export interface FlyDeployWizardDeps {
  process?: ForegroundProcessRunner;
  prompts?: DeployPromptPort;
  templateWriter?: TemplateWriter;
  qrRenderer?: QrCodeRendererPort;
  codexAuth?: OpenAICodexAuthAdapter;
}

export class FlyDeployWizard implements DeployWizardPort {
  private readonly runner: FlyDeployRunner;
  private readonly templateWriter: TemplateWriter;
  private readonly process: ForegroundProcessRunner;
  private readonly prompts: DeployPromptPort;
  private readonly qrRenderer: QrCodeRendererPort;
  private readonly codexAuth: OpenAICodexAuthAdapter;
  private readonly env: NodeJS.ProcessEnv;
  private readonly defaultAppName: string;
  private readonly modelLabels = new Map<string, string>();
  private readonly modelOptionsById = new Map<string, ModelOption>();
  private reasoningPolicies?: Map<string, ReasoningPolicy>;

  constructor(env?: NodeJS.ProcessEnv, deps: FlyDeployWizardDeps = {}) {
    this.env = this.buildChildEnv(env);
    this.process = deps.process ?? new NodeProcessRunner();
    this.runner = new FlyDeployRunner(this.process, this.env);
    this.templateWriter = deps.templateWriter ?? new TemplateWriter();
    this.prompts = deps.prompts ?? new ReadlineDeployPrompts();
    this.qrRenderer = deps.qrRenderer ?? new TerminalQrCodeRenderer();
    this.codexAuth = deps.codexAuth ?? new OpenAICodexAuthAdapter(this.process, this.env);
    this.defaultAppName = this.buildDefaultAppName();
    this.rememberModelOptions(STATIC_MODEL_OPTIONS);
  }

  async checkPlatform(): Promise<{ ok: boolean; error?: string }> {
    const platform = (this.env?.HERMES_FLY_PLATFORM ?? process.platform) as string;
    if (platform === "darwin" || platform === "linux") {
      return { ok: true };
    }
    return { ok: false, error: `Unsupported platform: ${platform}` };
  }

  async checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean; error?: string }> {
    if (await this.ensureFlyAvailable()) {
      return { ok: true };
    }
    if (!opts.autoInstall) {
      return { ok: false, missing: "fly", autoInstallDisabled: true };
    }

    this.prompts.write("I need the Fly.io command-line tool to create your deployment. Installing it now...\n");
    const installResult = await this.installFlyCli();
    if (!installResult.ok) {
      return {
        ok: false,
        missing: "fly",
        error: installResult.error ?? "Failed to install fly CLI automatically. Install it from https://fly.io/docs/flyctl/install/ and retry."
      };
    }

    if (!(await this.ensureFlyAvailable())) {
      return {
        ok: false,
        missing: "fly",
        error: "fly CLI installation completed, but the binary is still not available on PATH. Restart your shell or install manually from https://fly.io/docs/flyctl/install/."
      };
    }

    this.prompts.write("Fly.io CLI installed successfully.\n");
    return { ok: true };
  }

  async checkAuth(): Promise<{ ok: boolean; error?: string }> {
    let result = await this.process.run("fly", ["auth", "whoami"], { env: this.env });
    if (result.exitCode === 0) {
      return { ok: true };
    }

    if (!this.prompts.isInteractive()) {
      return { ok: false, error: "not authenticated" };
    }

    this.prompts.write("I need to connect your Fly.io account before deploying. Launching 'fly auth login' now...\n");
    this.prompts.write("A browser window may open so you can approve the login.\n");
    const loginResult = await this.process.runForeground("fly", ["auth", "login"], { env: this.env });
    if (loginResult.exitCode !== 0) {
      return { ok: false, error: "Fly.io authentication did not complete successfully." };
    }

    result = await this.process.run("fly", ["auth", "whoami"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "Fly.io authentication completed, but no active Fly.io session is available." };
    }
    this.prompts.write("Fly.io authentication complete.\n");
    return { ok: true };
  }

  async checkConnectivity(): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.run("fly", ["version"], { env: this.env });
    if (result.exitCode !== 0) {
      return { ok: false, error: "fly CLI unreachable" };
    }
    return { ok: true };
  }

  async collectConfig(opts: { channel: "stable" | "preview" | "edge" }): Promise<DeployConfig> {
    const env = this.env;
    if (this.prompts.isInteractive()) {
      this.prompts.write("\nHermes Agent Guided Setup\n");
      this.prompts.write("I'll walk you through the deployment setup step by step.\n");
      this.prompts.write("You can press Enter to accept a suggested option whenever one is shown.\n\n");
    }

    const orgSlug = await this.collectOrgSlug(env.HERMES_FLY_ORG ?? env.DEPLOY_ORG ?? env.FLY_ORG);
    const appName = await this.collectAppName(env.HERMES_FLY_APP_NAME);
    const region = await this.collectRegion(env.HERMES_FLY_REGION);
    const vmSize = await this.collectVmSize(env.HERMES_FLY_VM_SIZE);
    const volumeSize = await this.collectVolumeSize(env.HERMES_FLY_VOLUME_SIZE);
    const aiAccess = await this.collectAiAccess({
      provider: env.HERMES_LLM_PROVIDER ?? env.HERMES_FLY_PROVIDER,
      model: env.HERMES_FLY_MODEL,
      reasoningEffort: env.HERMES_REASONING_EFFORT,
      authJsonB64: env.HERMES_AUTH_JSON_B64,
    });
    const telegramSetup = await this.collectTelegramSetup({
      botToken: env.TELEGRAM_BOT_TOKEN,
      allowedUsers: env.TELEGRAM_ALLOWED_USERS,
      allowAllUsers: env.GATEWAY_ALLOW_ALL_USERS,
      homeChannel: env.TELEGRAM_HOME_CHANNEL,
    });
    const hermesRef = this.resolveHermesAgentRef(opts.channel);

    const intent = DeploymentIntent.create({
      appName,
      region,
      vmSize,
      provider: aiAccess.provider,
      model: aiAccess.model,
      reasoningEffort: aiAccess.reasoningEffort,
      channel: opts.channel
    });

    const config: DeployConfig = {
      orgSlug,
      appName: intent.appName,
      region: intent.region,
      vmSize: intent.vmSize,
      volumeSize,
      provider: intent.provider,
      apiKey: aiAccess.apiKey,
      authJsonB64: aiAccess.authJsonB64,
      model: intent.model,
      reasoningEffort: intent.reasoningEffort.length > 0 ? intent.reasoningEffort : undefined,
      channel: intent.channel,
      hermesRef,
      botToken: telegramSetup.botToken,
      telegramBotUsername: telegramSetup.botUsername,
      telegramBotName: telegramSetup.botName,
      telegramAllowedUsers: telegramSetup.allowedUsers,
      gatewayAllowAllUsers: telegramSetup.allowAllUsers ? true : undefined,
      telegramHomeChannel: telegramSetup.homeChannel,
    };

    if (this.prompts.isInteractive()) {
      await this.confirmConfig(config, telegramSetup);
    }

    return config;
  }

  async createBuildContext(config: DeployConfig): Promise<{ buildDir: string }> {
    const buildDir = join(tmpdir(), `hermes-deploy-${config.appName}-${Date.now()}`);
    await this.templateWriter.createBuildContext(config, buildDir);
    return { buildDir };
  }

  async provisionResources(config: DeployConfig): Promise<{ ok: boolean; error?: string }> {
    const appResult = await this.runner.createApp(config.appName, config.orgSlug);
    if (!appResult.ok) return appResult;

    const volResult = await this.runner.createVolume(config.appName, config.region, config.volumeSize);
    if (!volResult.ok) return volResult;

    const secrets: Record<string, string> = {
      LLM_MODEL: config.model,
      HERMES_AGENT_REF: config.hermesRef,
      HERMES_DEPLOY_CHANNEL: config.channel,
      HERMES_LLM_PROVIDER: config.provider,
      HERMES_APP_NAME: config.appName,
    };
    if (config.provider === "openrouter") {
      secrets.OPENROUTER_API_KEY = config.apiKey;
    }
    if (config.provider === "openai-codex" && config.authJsonB64) {
      secrets.HERMES_AUTH_JSON_B64 = config.authJsonB64;
    }
    if (config.reasoningEffort) {
      secrets.HERMES_REASONING_EFFORT = config.reasoningEffort;
    }
    if (config.botToken) {
      secrets.TELEGRAM_BOT_TOKEN = config.botToken;
    }
    if (config.telegramAllowedUsers) {
      secrets.TELEGRAM_ALLOWED_USERS = config.telegramAllowedUsers;
    }
    if (config.gatewayAllowAllUsers) {
      secrets.GATEWAY_ALLOW_ALL_USERS = "true";
    }
    if (config.telegramHomeChannel) {
      secrets.TELEGRAM_HOME_CHANNEL = config.telegramHomeChannel;
    }
    return this.runner.setSecrets(config.appName, secrets);
  }

  async runDeploy(buildDir: string, config: DeployConfig): Promise<{ ok: boolean; error?: string }> {
    const result = await this.process.runForeground(
      "fly",
      ["deploy", "--app", config.appName, "--config", "fly.toml", "--dockerfile", "Dockerfile", "--wait-timeout", "5m0s"],
      { env: this.env, cwd: buildDir }
    );
    if (result.exitCode !== 0) {
      return { ok: false, error: "fly deploy failed" };
    }
    return { ok: true };
  }

  async postDeployCheck(appName: string): Promise<{ ok: boolean; error?: string }> {
    let lastState = "unknown";

    for (let attempt = 0; attempt < 3; attempt += 1) {
      const result = await this.process.run("fly", ["machine", "list", "-a", appName, "--json"], { env: this.env });
      if (result.exitCode !== 0) {
        return { ok: false, error: "machine status check failed" };
      }

      const state = this.readPrimaryMachineState(result.stdout);
      if (state === "started") {
        return { ok: true };
      }
      if (state) {
        lastState = state;
      }
    }

    return { ok: false, error: `machine not running after deploy (${lastState})` };
  }

  async saveApp(appName: string, region: string): Promise<void> {
    const { readFile, writeFile, mkdir } = await import("node:fs/promises");
    const { join: pathJoin } = await import("node:path");
    const configDir = this.env.HERMES_FLY_CONFIG_DIR
      ?? `${this.env.HOME ?? process.env.HOME}/.hermes-fly`;
    await mkdir(configDir, { recursive: true });
    const configPath = pathJoin(configDir, "config.yaml");

    let existing = "";
    try { existing = await readFile(configPath, "utf8"); } catch { /* file may not exist */ }

    const allLines = existing.split(/\r?\n/).filter(l => l.trim() !== "");
    const withoutCurrentApp = allLines.filter(l => !/^current_app:/.test(l));

    const appsIdx = withoutCurrentApp.findIndex(l => /^apps:$/.test(l.trimEnd()));
    const preLines = appsIdx === -1 ? withoutCurrentApp : withoutCurrentApp.slice(0, appsIdx);
    const appsBodyRaw = appsIdx === -1 ? [] : withoutCurrentApp.slice(appsIdx + 1);

    const trailingStartIdx = appsBodyRaw.findIndex(l => !/^  /.test(l));
    const appsSectionLines = trailingStartIdx === -1 ? appsBodyRaw : appsBodyRaw.slice(0, trailingStartIdx);
    const trailingTopLevelLines = trailingStartIdx === -1 ? [] : appsBodyRaw.slice(trailingStartIdx);

    const entries: { name: string; lines: string[] }[] = [];
    let current: { name: string; lines: string[] } | null = null;
    for (const line of appsSectionLines) {
      const m = line.match(/^  - name:[ \t]*(.+)$/);
      if (m) {
        if (current !== null) entries.push(current);
        current = { name: m[1].trim(), lines: [line] };
      } else if (current !== null) {
        current.lines.push(line);
      }
    }
    if (current !== null) entries.push(current);

    const filtered = entries.filter(e => e.name !== appName);
    filtered.push({ name: appName, lines: [`  - name: ${appName}`, `    region: ${region}`] });

    const newLines = [
      `current_app: ${appName}`,
      ...preLines,
      "apps:",
      ...filtered.flatMap(e => e.lines),
      ...trailingTopLevelLines,
    ];
    await writeFile(configPath, newLines.join("\n") + "\n", "utf8");
  }

  async chooseSuccessfulDeploymentAction(config: DeployConfig): Promise<"conclude" | "destroy"> {
    if (!this.prompts.isInteractive()) {
      return "conclude";
    }

    this.prompts.write("\nWhat would you like to do next?\n\n");
    this.prompts.write("   1  Conclude and keep it  Finish here and leave the new deployment running.\n");
    if (config.botToken) {
      this.prompts.write("   2  Destroy it now        Remove the Fly deployment now and hand off Telegram bot deletion to BotFather.\n\n");
    } else {
      this.prompts.write("   2  Destroy it now        Remove the Fly deployment and attached Fly resources now.\n\n");
    }

    const choice = await this.chooseNumber("Choose an option [1]: ", 2, 1);
    if (choice === 1) {
      return "conclude";
    }

    const confirmed = await this.confirmYesNo(`Destroy ${config.appName} now? [y/N]: `, false);
    if (!confirmed) {
      this.prompts.write("Keeping the deployment.\n");
      return "conclude";
    }

    return "destroy";
  }

  async showTelegramBotDeletionGuidance(config: DeployConfig): Promise<void> {
    if (!config.botToken) {
      return;
    }

    this.prompts.write("\nTelegram bot cleanup\n");
    this.prompts.write("Telegram does not document any Bot API method that permanently deletes a bot.\n");
    this.prompts.write("The Fly deployment has been destroyed.\n");
    if (config.telegramBotUsername) {
      this.prompts.write(`To finish deleting @${config.telegramBotUsername}, open BotFather with /deletebot prefilled:\n`);
    } else {
      this.prompts.write("To finish deleting the Telegram bot itself, open BotFather with /deletebot prefilled:\n");
    }
    this.prompts.write(`${TELEGRAM_BOTFATHER_DELETEBOT_URL}\n`);
    this.prompts.write("Scan this QR code with your phone to open BotFather with /deletebot ready to send:\n\n");
    try {
      const qr = await this.qrRenderer.render(TELEGRAM_BOTFATHER_DELETEBOT_URL);
      this.prompts.write(`${qr}\n`);
    } catch {
      this.prompts.write("(QR code unavailable in this terminal. Use the direct link above.)\n\n");
    }
    this.prompts.write("If Telegram opens the chat without sending anything, tap Send to submit /deletebot.\n");
    if (config.telegramBotUsername) {
      this.prompts.write(`When BotFather asks which bot to delete, choose @${config.telegramBotUsername}.\n`);
    }
    this.prompts.write("Guide: https://core.telegram.org/bots#6-botfather\n");
  }

  private async collectAppName(envValue: string | undefined): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return this.validateAppName(preset);
    }
    if (!this.prompts.isInteractive()) {
      return this.defaultAppName;
    }

    this.prompts.write("Each deployment needs a unique name on Fly.io.\n");
    this.prompts.write("This name is only for the server setup. People chatting with your agent will not see it.\n\n");
    this.prompts.write(`Suggested: ${this.defaultAppName}\n`);
    this.prompts.write("Press Enter to use it, or type your own.\n\n");

    while (true) {
      const answer = await this.prompts.ask(`Deployment name [${this.defaultAppName}]: `);
      const value = answer.length > 0 ? answer : this.defaultAppName;
      try {
        return this.validateAppName(value);
      } catch (error) {
        this.prompts.write(`${error instanceof Error ? error.message : "Deployment name is invalid."}\n`);
      }
    }
  }

  private readPrimaryMachineState(stdout: string): string | undefined {
    try {
      const parsed = JSON.parse(stdout) as Array<{ state?: unknown; State?: unknown }>;
      if (!Array.isArray(parsed) || parsed.length === 0) {
        return undefined;
      }
      const states = parsed
        .map((machine) => machine.state ?? machine.State)
        .filter((state): state is string => typeof state === "string");
      if (states.includes("started")) {
        return "started";
      }
      return states[0];
    } catch {
      return undefined;
    }
  }

  private resolveHermesAgentRef(channel: "stable" | "preview" | "edge"): string {
    const override = (this.env.HERMES_AGENT_REF ?? "").trim();
    if (override.length > 0) {
      return override;
    }

    switch (channel) {
      case "edge":
        return HERMES_AGENT_EDGE_REF;
      case "preview":
        return HERMES_AGENT_PREVIEW_REF;
      default:
        return HERMES_AGENT_DEFAULT_REF;
    }
  }

  private async collectOrgSlug(envValue: string | undefined): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return preset;
    }

    const orgs = await this.fetchFlyOrganizations();
    if (orgs.length === 0) {
      throw new Error("No Fly.io organizations were found for the current account.");
    }

    if (orgs.length === 1) {
      if (this.prompts.isInteractive()) {
        this.prompts.write(`Fly.io organization: ${orgs[0].name} (${orgs[0].slug})\n\n`);
      }
      return orgs[0].slug;
    }

    if (!this.prompts.isInteractive()) {
      throw new Error(
        `Multiple Fly.io organizations found. Export HERMES_FLY_ORG to one of: ${orgs.map((org) => org.slug).join(", ")}.`
      );
    }

    this.prompts.write("Which Fly.io organization should own this deployment?\n");
    this.prompts.write("If you only use Fly personally, the Personal organization is usually the right choice.\n\n");
    this.prompts.write("  #  Organization                Slug\n");
    orgs.forEach((org, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${org.name.padEnd(26, " ")} ${org.slug}\n`);
    });
    this.prompts.write("\n");

    const defaultIndex = Math.max(0, orgs.findIndex((org) => org.type?.toUpperCase() === "PERSONAL"));
    const selected = orgs[await this.chooseNumber(`Choose an organization [${defaultIndex + 1}]: `, orgs.length, defaultIndex + 1) - 1];
    return selected.slug;
  }

  private async collectRegion(envValue: string | undefined): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return DEFAULT_REGION;
    }

    const regions = await this.fetchRegions();
    const areaRows = REGION_AREA_ORDER
      .map((area) => ({ area, options: regions.filter((region) => region.area === area) }))
      .filter((row) => row.options.length > 0);

    this.prompts.write("Where are you (or most of your users) located?\n");
    this.prompts.write("Choosing a closer server usually means faster responses.\n\n");
    this.prompts.write("  #  Area            Locations\n");
    areaRows.forEach((row, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${row.area.padEnd(15, " ")} ${String(row.options.length).padStart(2, " ")}\n`);
    });
    this.prompts.write("\n");

    const defaultAreaIndex = Math.max(0, areaRows.findIndex((row) => row.options.some((option) => option.code === DEFAULT_REGION)));
    const selectedArea = areaRows[await this.chooseNumber(`Choose an area [${defaultAreaIndex + 1}]: `, areaRows.length, defaultAreaIndex + 1) - 1];

    this.prompts.write(`\n${selectedArea.area} locations:\n\n`);
    this.prompts.write("  #  Location                          Code\n");
    selectedArea.options.forEach((region, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${region.name.padEnd(32, " ")} ${region.code}\n`);
    });
    this.prompts.write("\n");

    const defaultLocationIndex = Math.max(0, selectedArea.options.findIndex((region) => region.code === DEFAULT_REGION));
    const selectedLocation = selectedArea.options[await this.chooseNumber(`Choose a location [${defaultLocationIndex + 1}]: `, selectedArea.options.length, defaultLocationIndex + 1) - 1];
    return selectedLocation.code;
  }

  private async fetchFlyOrganizations(): Promise<FlyOrgOption[]> {
    const result = await this.process.run("fly", ["orgs", "list", "--json"], { env: this.env });
    if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
      throw new Error("Failed to fetch Fly.io organizations.");
    }

    try {
      const parsed = JSON.parse(result.stdout) as unknown;
      if (Array.isArray(parsed)) {
        return parsed
          .flatMap((value) => {
            if (!value || typeof value !== "object") {
              return [];
            }
            const slug = String((value as { slug?: unknown }).slug ?? "").trim();
            const name = String((value as { name?: unknown }).name ?? slug).trim();
            const type = String((value as { type?: unknown }).type ?? "").trim() || undefined;
            if (slug.length === 0) {
              return [];
            }
            return [{ slug, name: name.length > 0 ? name : slug, type }];
          });
      }

      if (parsed && typeof parsed === "object") {
        return Object.entries(parsed as Record<string, unknown>)
          .flatMap(([slug, name]) => {
            const cleanSlug = slug.trim();
            const cleanName = String(name ?? slug).trim();
            if (cleanSlug.length === 0) {
              return [];
            }
            return [{ slug: cleanSlug, name: cleanName.length > 0 ? cleanName : cleanSlug }];
          });
      }
    } catch {
      throw new Error("Fly.io organizations response could not be parsed.");
    }

    throw new Error("Fly.io organizations response was empty.");
  }

  private async collectVmSize(envValue: string | undefined): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return DEFAULT_VM_SIZE;
    }

    const options = await this.fetchVmOptions();
    const defaultIndex = Math.max(0, options.findIndex((option) => option.value === DEFAULT_VM_SIZE));

    this.prompts.write("How powerful should your agent's server be?\n\n");
    this.prompts.write("  #  Tier       Specs           Est. cost  Best for\n");
    options.forEach((option, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${option.tier.padEnd(10, " ")} ${option.ramLabel.padEnd(14, " ")} ${option.costLabel.padEnd(10, " ")} ${option.bestFor}\n`);
    });
    this.prompts.write("\nPrices are estimates. Check current rates: https://fly.io/calculator\n\n");

    const selected = options[await this.chooseNumber(`Choose a tier [${defaultIndex + 1}]: `, options.length, defaultIndex + 1) - 1];
    return selected.value;
  }

  private async collectVolumeSize(envValue: string | undefined): Promise<number> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      return this.parseVolumeSize(preset, "HERMES_FLY_VOLUME_SIZE");
    }
    if (!this.prompts.isInteractive()) {
      return DEFAULT_VOLUME_SIZE;
    }

    const defaultIndex = Math.max(0, STATIC_VOLUME_OPTIONS.findIndex((option) => option.value === DEFAULT_VOLUME_SIZE));

    this.prompts.write("How much storage should your agent have?\n");
    this.prompts.write("This is where your agent saves conversations, memories, and files.\n\n");
    this.prompts.write("  #  Size   Est. cost   Best for\n");
    STATIC_VOLUME_OPTIONS.forEach((option, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${String(option.value).padStart(2, " ")} GB  ${option.costLabel.padEnd(10, " ")} ${option.bestFor}\n`);
    });
    this.prompts.write("\nPrices are estimates. Check current rates: https://fly.io/calculator\n\n");

    const selected = STATIC_VOLUME_OPTIONS[await this.chooseNumber(`Choose a size [${defaultIndex + 1}]: `, STATIC_VOLUME_OPTIONS.length, defaultIndex + 1) - 1];
    return selected.value;
  }

  private async collectAiAccess(input: {
    provider?: string;
    model?: string;
    reasoningEffort?: string;
    authJsonB64?: string;
  }): Promise<AiAccessSelection> {
    const normalizedProvider = this.normalizeAiProvider(input.provider);
    if (normalizedProvider === "openrouter") {
      return this.collectOpenRouterAccess(input.model, input.reasoningEffort);
    }
    if (normalizedProvider === "openai-codex") {
      return this.collectOpenAICodexAccess(input.model, input.reasoningEffort, input.authJsonB64);
    }

    if (!this.prompts.isInteractive()) {
      const bundledCodexAuth = (input.authJsonB64 ?? "").trim();
      if (bundledCodexAuth.length > 0) {
        return this.collectOpenAICodexAccess(input.model, input.reasoningEffort, bundledCodexAuth);
      }
      return this.collectOpenRouterAccess(input.model, input.reasoningEffort);
    }

    this.prompts.write("How should Hermes access AI models?\n");
    this.prompts.write("You can use your own OpenRouter API key, or sign in with your ChatGPT subscription through OpenAI Codex.\n\n");
    this.prompts.write("   1  OpenRouter API key         Bring your own API key and choose from OpenRouter's model catalog\n");
    this.prompts.write("   2  ChatGPT subscription       Sign in with ChatGPT / OpenAI through OpenAI Codex\n\n");

    const selection = await this.chooseNumber("Choose an option [1]: ", 2, 1);
    if (selection === 2) {
      return this.collectOpenAICodexAccess(input.model, input.reasoningEffort, input.authJsonB64);
    }
    return this.collectOpenRouterAccess(input.model, input.reasoningEffort);
  }

  private async collectOpenRouterAccess(
    envModel: string | undefined,
    envReasoningEffort: string | undefined
  ): Promise<AiAccessSelection> {
    const apiKey = await this.collectOpenRouterApiKey();
    const model = await this.collectModel(envModel, apiKey);
    const reasoningEffort = await this.collectReasoningEffort(envReasoningEffort, model);
    return {
      provider: "openrouter",
      apiKey,
      model,
      reasoningEffort,
    };
  }

  private async collectOpenAICodexAccess(
    envModel: string | undefined,
    envReasoningEffort: string | undefined,
    bundledAuthJsonB64?: string
  ): Promise<AiAccessSelection> {
    const auth = await this.collectCodexAuth(bundledAuthJsonB64);
    const model = await this.collectCodexModel(envModel, auth.accessToken);
    const reasoningEffort = await this.collectReasoningEffort(envReasoningEffort, model);
    return {
      provider: "openai-codex",
      apiKey: "",
      authJsonB64: auth.authJsonB64,
      model,
      reasoningEffort,
    };
  }

  private async collectCodexAuth(bundledAuthJsonB64?: string): Promise<ResolvedCodexAuth> {
    const providedAuth = (bundledAuthJsonB64 ?? "").trim();
    if (providedAuth.length > 0) {
      return {
        source: "hermes",
        accessToken: this.accessTokenFromEncodedCodexAuth(providedAuth),
        authJsonB64: providedAuth,
      };
    }

    const stored = await this.codexAuth.resolveStoredAuth();
    if (!this.prompts.isInteractive()) {
      if (stored) {
        return stored;
      }
      throw new Error("OpenAI Codex credentials are required in non-interactive mode. Export HERMES_AUTH_JSON_B64 or sign in interactively first.");
    }

    if (!stored) {
      return this.codexAuth.runDeviceCodeLogin(this.prompts);
    }

    if (stored.source === "hermes") {
      this.prompts.write("I found an existing Hermes OpenAI Codex login on this machine.\n\n");
      this.prompts.write("   1  Reuse it        Use the saved ChatGPT subscription login for this deployment\n");
      this.prompts.write("   2  Sign in again   Start a fresh OpenAI Codex login now\n\n");
      const choice = await this.chooseNumber("Choose an option [1]: ", 2, 1);
      if (choice === 1) {
        return stored;
      }
      return this.codexAuth.runDeviceCodeLogin(this.prompts);
    }

    this.prompts.write("I found an existing Codex login on this machine.\n");
    this.prompts.write("Hermes can import it into its own auth store for this deployment.\n\n");
    this.prompts.write("   1  Import and use it   Reuse the saved Codex login\n");
    this.prompts.write("   2  Sign in again       Start a fresh OpenAI Codex login now\n\n");
    const choice = await this.chooseNumber("Choose an option [1]: ", 2, 1);
    if (choice === 1) {
      return stored;
    }
    return this.codexAuth.runDeviceCodeLogin(this.prompts);
  }

  private async collectCodexModel(envValue: string | undefined, accessToken: string): Promise<string> {
    const preset = envValue?.trim();
    const models = await this.fetchCodexModels(accessToken, this.prompts.isInteractive());
    if (preset && preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return models[0]?.value ?? "gpt-5.3-codex";
    }

    this.prompts.write("Which OpenAI Codex model should your agent use?\n\n");
    models.forEach((option, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${option.label.padEnd(24, " ")} ${option.bestFor}\n`);
    });
    const manualIndex = models.length + 1;
    this.prompts.write(`  ${String(manualIndex).padStart(2, " ")}  Bring my own model        Enter a model ID manually\n\n`);

    const selectedIndex = await this.chooseNumber("Choose a model [1]: ", manualIndex, 1);
    if (selectedIndex === manualIndex) {
      this.prompts.write("Model IDs come from the OpenAI Codex catalog. Example: gpt-5.3-codex\n\n");
      while (true) {
        const answer = (await this.prompts.ask("Model ID: ")).trim();
        if (answer.length > 0) {
          return answer;
        }
        this.prompts.write("Model ID cannot be empty.\n");
      }
    }

    return models[selectedIndex - 1].value;
  }

  private async fetchCodexModels(accessToken: string, announce: boolean): Promise<CodexModelOption[]> {
    if (announce) {
      this.prompts.write("Fetching available Codex models from OpenAI...\n");
    }

    const models = await this.codexAuth.fetchModels(accessToken);
    this.rememberModelOptions(models.map((option) => ({
      value: option.value,
      label: option.label,
      bestFor: option.bestFor,
      providerKey: option.providerKey,
      providerLabel: option.providerLabel,
      supportsReasoning: option.supportsReasoning,
    })));
    return models;
  }

  private accessTokenFromEncodedCodexAuth(authJsonB64: string): string {
    try {
      const raw = Buffer.from(authJsonB64, "base64").toString("utf8");
      const parsed = JSON.parse(raw) as { providers?: Record<string, unknown> };
      const state = parsed.providers?.["openai-codex"];
      const tokens = typeof state === "object" && state !== null ? (state as { tokens?: unknown }).tokens : undefined;
      const accessToken = typeof tokens === "object" && tokens !== null ? String((tokens as { access_token?: unknown }).access_token ?? "").trim() : "";
      if (accessToken.length > 0) {
        return accessToken;
      }
    } catch {
      // handled below
    }
    throw new Error("HERMES_AUTH_JSON_B64 does not contain valid OpenAI Codex credentials.");
  }

  private normalizeAiProvider(value: string | undefined): "openrouter" | "openai-codex" | undefined {
    const normalized = (value ?? "").trim().toLowerCase();
    if (normalized === "openrouter") {
      return "openrouter";
    }
    if (normalized === "openai-codex" || normalized === "codex" || normalized === "chatgpt") {
      return "openai-codex";
    }
    return undefined;
  }

  private async collectOpenRouterApiKey(): Promise<string> {
    const envKey = "OPENROUTER_API_KEY";
    const preset = (this.env[envKey] ?? "").trim();
    if (preset.length > 0) {
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      throw new Error(`${envKey} is required in non-interactive mode. Run from a terminal to use the guided wizard or export ${envKey} first.`);
    }

    this.prompts.write(`Get your OpenRouter API key at: ${OPENROUTER_KEY_URL}\n`);
    this.prompts.write("This key lets your deployed agent call the AI model you choose.\n\n");
    while (true) {
      const answer = await this.prompts.askSecret("OpenRouter API key (required): ");
      const apiKey = answer.trim();
      if (apiKey.length === 0) {
        this.prompts.write(`${envKey} cannot be empty.\n`);
        continue;
      }

      const validation = await this.validateOpenRouterKey(apiKey);
      if (!validation.ok) {
        this.prompts.write("OpenRouter rejected this key. Check it and try again.\n");
        continue;
      }
      if (validation.warning) {
        this.prompts.write(`${validation.warning}\n`);
      }
      return apiKey;
    }
  }

  private async collectModel(envValue: string | undefined, apiKey: string): Promise<string> {
    const preset = envValue?.trim();
    if (preset && preset.length > 0) {
      await this.fetchCuratedOpenRouterModels(apiKey, false);
      return preset;
    }
    if (!this.prompts.isInteractive()) {
      return DEFAULT_MODEL;
    }

    const catalog = await this.fetchCuratedOpenRouterModels(apiKey, true);
    const provider = await this.collectProviderChoice(catalog);
    const providerModels = catalog.filter((option) => option.providerKey === provider.key);
    return await this.collectProviderModelChoice(provider, providerModels);
  }

  private async collectReasoningEffort(envValue: string | undefined, modelId: string): Promise<string | undefined> {
    const preset = envValue?.trim().toLowerCase();
    const support = await this.resolveReasoningSupport(modelId);

    if (preset && preset.length > 0) {
      if (!support.supported) {
        throw new Error(`HERMES_REASONING_EFFORT is not supported for model ${modelId}.`);
      }
      if (!support.allowedEfforts.includes(preset)) {
        throw new Error(
          `HERMES_REASONING_EFFORT must be one of ${support.allowedEfforts.join("|")} for model ${modelId}.`
        );
      }
      return preset;
    }

    if (!support.supported) {
      if (support.unsupportedMessage && this.prompts.isInteractive()) {
        this.prompts.write(`${support.unsupportedMessage}\n\n`);
      }
      return undefined;
    }

    if (!support.defaultEffort) {
      return undefined;
    }

    if (!this.prompts.isInteractive()) {
      return support.defaultEffort;
    }

    if (support.allowedEfforts.length === 1) {
      this.prompts.write(`Hermes will use the only supported reasoning effort for this model: ${support.allowedEfforts[0]}.\n\n`);
      return support.allowedEfforts[0];
    }

    const defaultIndex = Math.max(0, support.allowedEfforts.findIndex((effort) => effort === support.defaultEffort));
    this.prompts.write("How much extra reasoning effort should Hermes use with this model?\n");
    this.prompts.write("Higher effort can help on harder tasks, but it may respond slower and cost more.\n\n");
    support.allowedEfforts.forEach((effort, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${this.describeReasoningEffort(effort)}\n`);
    });
    this.prompts.write("\n");

    const selectedIndex = await this.chooseNumber(
      `Choose a reasoning level [${defaultIndex + 1}]: `,
      support.allowedEfforts.length,
      defaultIndex + 1
    );
    return support.allowedEfforts[selectedIndex - 1];
  }

  private async collectProviderChoice(catalog: ModelOption[]): Promise<ProviderOption> {
    const providers = this.buildProviderOptions(catalog);
    const defaultIndex = Math.max(0, providers.findIndex((provider) => provider.key === "anthropic"));

    this.prompts.write("Which AI provider do you want to use through OpenRouter?\n");
    this.prompts.write("You'll pick a specific model from that provider next.\n\n");
    providers.forEach((provider, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${provider.label.padEnd(12, " ")} ${provider.description}\n`);
    });
    this.prompts.write("\n");

    const selectedIndex = await this.chooseNumber(`Choose a provider [${defaultIndex + 1}]: `, providers.length, defaultIndex + 1);
    return providers[selectedIndex - 1];
  }

  private async collectProviderModelChoice(provider: ProviderOption, models: ModelOption[]): Promise<string> {
    this.prompts.write(`Which ${provider.label} model should your agent use?\n\n`);
    models.forEach((option, index) => {
      this.prompts.write(`  ${String(index + 1).padStart(2, " ")}  ${option.label.padEnd(24, " ")} ${option.bestFor}\n`);
    });
    const manualIndex = models.length + 1;
    this.prompts.write(`  ${String(manualIndex).padStart(2, " ")}  Bring my own model        Enter a model ID manually\n\n`);

    const selectedIndex = await this.chooseNumber(`Choose a model [1]: `, manualIndex, 1);
    if (selectedIndex === manualIndex) {
      this.prompts.write(`Find model IDs at ${OPENROUTER_MODELS_URL}\n`);
      this.prompts.write("Example: anthropic/claude-3-5-sonnet\n\n");
      while (true) {
        const answer = (await this.prompts.ask("Model ID: ")).trim();
        if (answer.length > 0) {
          return answer;
        }
        this.prompts.write("Model ID cannot be empty.\n");
      }
    }

    return models[selectedIndex - 1].value;
  }

  private async collectTelegramSetup(input: {
    botToken?: string;
    allowedUsers?: string;
    allowAllUsers?: string;
    homeChannel?: string;
  }): Promise<TelegramSetup> {
    const presetToken = (input.botToken ?? "").trim();
    if (presetToken.length > 0) {
      await this.assertTelegramTokenFormat(presetToken);
      const identity = await this.validateTelegramBotToken(presetToken);
      if (!identity) {
        throw new Error("Telegram rejected TELEGRAM_BOT_TOKEN. Check it and try again.");
      }
      return this.buildTelegramSetupFromInputs(
        presetToken,
        identity,
        input.allowedUsers,
        input.allowAllUsers,
        input.homeChannel
      );
    }

    if (!this.prompts.isInteractive()) {
      return { botToken: "" };
    }

    this.prompts.write("Do you want to connect Telegram now?\n");
    this.prompts.write("You can skip this and set it up later if you prefer.\n\n");
    this.prompts.write("   1  Telegram now   Chat with your agent in Telegram\n");
    this.prompts.write("   2  Skip for now   Finish deployment first\n\n");

    const choice = await this.chooseNumber("Choose an option [2]: ", 2, 2);
    if (choice === 2) {
      return { botToken: "" };
    }

    this.prompts.write("Create your Telegram bot with BotFather, then paste the bot token here.\n");
    this.prompts.write(`Open BotFather directly with /newbot prefilled: ${TELEGRAM_BOTFATHER_NEWBOT_URL}\n`);
    this.prompts.write("Scan this QR code with your phone to open BotFather with /newbot ready to send:\n\n");
    try {
      const qr = await this.qrRenderer.render(TELEGRAM_BOTFATHER_NEWBOT_URL);
      this.prompts.write(`${qr}\n`);
    } catch {
      this.prompts.write("(QR code unavailable in this terminal. Use the direct link above.)\n\n");
    }
    this.prompts.write("If Telegram opens the chat without sending anything, tap Send to submit /newbot.\n");
    this.prompts.write("Guide: https://core.telegram.org/bots#6-botfather\n\n");

    while (true) {
      const token = (await this.prompts.askSecret("Telegram bot token (required): ")).trim();
      if (token.length === 0) {
        this.prompts.write("TELEGRAM_BOT_TOKEN cannot be empty.\n");
        continue;
      }

      if (!this.isTelegramTokenFormatValid(token)) {
        this.prompts.write("Telegram bot token format looks invalid. Expected format: 123456789:ABCdef...\n");
        continue;
      }

      this.prompts.write("Verifying your bot token with Telegram...\n");
      const identity = await this.validateTelegramBotToken(token);
      if (!identity) {
        this.prompts.write("Telegram rejected this bot token. Check it and try again.\n");
        continue;
      }

      this.prompts.write(`Found bot: @${identity.username} (${identity.firstName})\n`);
      if (!(await this.confirmYesNo("Continue with this bot? [y/N]: ", false))) {
        continue;
      }

      const accessPolicy = await this.collectTelegramAccessPolicy();
      const homeChannel = accessPolicy.allowedUsers.length > 0
        ? await this.collectTelegramHomeChannel(accessPolicy.allowedUsers[0])
        : undefined;

      return {
        botToken: token,
        botUsername: identity.username,
        botName: identity.firstName,
        allowedUsers: accessPolicy.allowedUsers.join(","),
        allowAllUsers: accessPolicy.mode === "anyone",
        homeChannel,
      };
    }
  }

  private async confirmConfig(config: DeployConfig, telegramSetup: TelegramSetup): Promise<void> {
    this.prompts.write("\nReview your setup\n");
    this.prompts.write(`  Fly organization: ${config.orgSlug}\n`);
    this.prompts.write(`  Deployment name: ${config.appName}\n`);
    this.prompts.write(`  Location:        ${config.region}\n`);
    this.prompts.write(`  Server size:     ${this.describeVmSize(config.vmSize)}\n`);
    this.prompts.write(`  Storage:         ${config.volumeSize} GB\n`);
    this.prompts.write(`  AI access:       ${this.describeAiAccess(config.provider)}\n`);
    this.prompts.write(`  AI model:        ${this.describeModel(config.model)}\n`);
    if (config.reasoningEffort) {
      this.prompts.write(`  Reasoning:       ${config.reasoningEffort}\n`);
    }
    if (config.botToken) {
      this.prompts.write(`  Telegram:        ${this.describeTelegramBot(telegramSetup)}\n`);
      this.prompts.write(`  Telegram access: ${this.describeTelegramAccess(config)}\n`);
      if (config.telegramHomeChannel) {
        this.prompts.write(`  Home channel:    ${config.telegramHomeChannel}\n`);
      }
    } else {
      this.prompts.write("  Telegram:        skip for now\n");
    }
    this.prompts.write(`  Release channel: ${config.channel || DEFAULT_CHANNEL}\n\n`);

    while (true) {
      const answer = (await this.prompts.ask("Continue with deployment? [Y/n]: ")).trim().toLowerCase();
      if (answer.length === 0 || answer === "y" || answer === "yes") {
        return;
      }
      if (answer === "n" || answer === "no") {
        throw new Error("Deployment cancelled.");
      }
      this.prompts.write("Please answer Y or n.\n");
    }
  }

  private async chooseNumber(prompt: string, max: number, fallback: number): Promise<number> {
    while (true) {
      const answer = (await this.prompts.ask(prompt)).trim();
      const value = answer.length > 0 ? Number(answer) : fallback;
      if (Number.isInteger(value) && value >= 1 && value <= max) {
        return value;
      }
      this.prompts.write(`Please enter a number between 1 and ${max}.\n`);
    }
  }

  private async confirmYesNo(prompt: string, defaultYes: boolean): Promise<boolean> {
    while (true) {
      const answer = (await this.prompts.ask(prompt)).trim().toLowerCase();
      if (answer.length === 0) {
        return defaultYes;
      }
      if (answer === "y" || answer === "yes") {
        return true;
      }
      if (answer === "n" || answer === "no") {
        return false;
      }
      this.prompts.write("Please answer y or n.\n");
    }
  }

  private isTelegramTokenFormatValid(token: string): boolean {
    return /^[0-9]+:[A-Za-z0-9_-]+$/.test(token);
  }

  private async assertTelegramTokenFormat(token: string): Promise<void> {
    if (!this.isTelegramTokenFormatValid(token)) {
      throw new Error("TELEGRAM_BOT_TOKEN must match the format 123456789:ABCdef...");
    }
  }

  private async validateTelegramBotToken(token: string): Promise<TelegramBotIdentity | null> {
    try {
      const result = await this.process.run(
        "curl",
        ["-fsSL", "--max-time", "10", `https://api.telegram.org/bot${token}/getMe`],
        { env: this.env }
      );
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return null;
      }

      const payload = JSON.parse(result.stdout) as {
        ok?: boolean;
        result?: { username?: unknown; first_name?: unknown; firstName?: unknown };
      };
      if (payload.ok !== true) {
        return null;
      }

      const username = String(payload.result?.username ?? "").trim();
      if (username.length === 0) {
        return null;
      }

      const firstName = String(payload.result?.first_name ?? payload.result?.firstName ?? username).trim() || username;
      return { username, firstName };
    } catch {
      return null;
    }
  }

  private async collectTelegramAccessPolicy(): Promise<MessagingPolicy> {
    while (true) {
      this.prompts.write("\nWho should be able to talk to this bot?\n\n");
      this.prompts.write("   1  Only me          Just you. You'll enter your Telegram user ID.\n");
      this.prompts.write("   2  Specific people  You and other approved users.\n");
      this.prompts.write("   3  Anyone           No restrictions. Not recommended for most setups.\n\n");

      const choice = await this.chooseNumber("Choose an option [1]: ", 3, 1);
      if (choice === 1) {
        this.prompts.write(`Find your Telegram user ID here: ${TELEGRAM_USERINFOBOT_URL}\n\n`);
        return await this.collectTelegramUserIds("only_me", "Your Telegram user ID: ");
      }
      if (choice === 2) {
        this.prompts.write(`Find Telegram user IDs here: ${TELEGRAM_USERINFOBOT_URL}\n\n`);
        return await this.collectTelegramUserIds("specific_users", "Telegram user IDs (comma-separated): ");
      }
      if (await this.confirmYesNo("Allow anyone to use this bot? This is not recommended for most setups. [y/N]: ", false)) {
        return MessagingPolicy.create("anyone", []);
      }
    }
  }

  private async collectTelegramUserIds(mode: MessagingPolicyMode, prompt: string): Promise<MessagingPolicy> {
    while (true) {
      const answer = (await this.prompts.ask(prompt)).trim();
      try {
        return this.buildMessagingPolicy(mode, answer);
      } catch {
        this.prompts.write("Telegram user IDs must be numeric. Use commas to separate multiple IDs.\n");
      }
    }
  }

  private buildMessagingPolicy(mode: MessagingPolicyMode, raw: string): MessagingPolicy {
    const pieces = raw
      .split(",")
      .map((part) => part.trim())
      .filter((part) => part.length > 0);

    if (pieces.some((part) => !/^[0-9]+$/.test(part))) {
      throw new Error("Telegram user IDs must be numeric.");
    }

    const userIds = pieces.map((part) => Number(part));
    return MessagingPolicy.create(mode, userIds);
  }

  private async collectTelegramHomeChannel(defaultUserId: number): Promise<string | undefined> {
    this.prompts.write("\nHermes can also use Telegram for its own status updates.\n");
    const useDefault = await this.confirmYesNo(
      `Use ${defaultUserId} as the home channel for bot status messages? [y/N]: `,
      false
    );
    return useDefault ? String(defaultUserId) : undefined;
  }

  private buildTelegramSetupFromInputs(
    botToken: string,
    identity: TelegramBotIdentity | null,
    allowedUsersInput: string | undefined,
    allowAllUsersInput: string | undefined,
    homeChannelInput: string | undefined
  ): TelegramSetup {
    const allowAllUsers = /^(1|true|yes)$/i.test((allowAllUsersInput ?? "").trim());
    const allowedUsersRaw = (allowedUsersInput ?? "").trim();
    const homeChannelRaw = (homeChannelInput ?? "").trim();

    if (allowAllUsers && allowedUsersRaw.length > 0) {
      throw new Error("TELEGRAM_ALLOWED_USERS cannot be set when GATEWAY_ALLOW_ALL_USERS is true.");
    }

    let allowedUsers: string | undefined;
    if (allowedUsersRaw.length > 0) {
      const mode: MessagingPolicyMode = allowedUsersRaw.includes(",") ? "specific_users" : "only_me";
      const policy = this.buildMessagingPolicy(mode, allowedUsersRaw);
      allowedUsers = policy.allowedUsers.join(",");
    }

    if (homeChannelRaw.length > 0 && !/^[0-9]+$/.test(homeChannelRaw)) {
      throw new Error("TELEGRAM_HOME_CHANNEL must be a numeric Telegram user ID.");
    }

    return {
      botToken,
      botUsername: identity?.username,
      botName: identity?.firstName,
      allowedUsers,
      allowAllUsers,
      homeChannel: homeChannelRaw.length > 0 ? homeChannelRaw : undefined,
    };
  }

  private validateAppName(value: string): string {
    const normalized = value.trim().toLowerCase();
    if (normalized.length < 2 || normalized.length > 63) {
      throw new Error("Deployment name must be between 2 and 63 characters.");
    }
    if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(normalized)) {
      throw new Error("Deployment name must start with a letter and use only lowercase letters, numbers, and hyphens.");
    }
    return normalized;
  }

  private describeVmSize(vmSize: string): string {
    const match = STATIC_VM_OPTIONS.find((option) => option.value === vmSize);
    return match ? `${match.tier} (${vmSize}, ${match.ramLabel})` : vmSize;
  }

  private describeModel(model: string): string {
    const label = this.modelLabels.get(model);
    return label ? `${label} (${model})` : model;
  }

  private describeAiAccess(provider: string): string {
    if (provider === "openai-codex") {
      return "ChatGPT subscription (OpenAI Codex)";
    }
    return "OpenRouter API key";
  }

  private describeTelegramBot(setup: TelegramSetup): string {
    if (setup.botUsername) {
      return `@${setup.botUsername}`;
    }
    return "set up now";
  }

  private describeTelegramAccess(config: DeployConfig): string {
    if (config.gatewayAllowAllUsers) {
      return "Anyone";
    }
    if (!config.telegramAllowedUsers) {
      return "Set up now";
    }

    const users = config.telegramAllowedUsers.split(",").map((value) => value.trim()).filter(Boolean);
    if (users.length === 1) {
      return `Only me (${users[0]})`;
    }
    return `Specific people (${users.join(", ")})`;
  }

  private parseVolumeSize(value: string, label: string): number {
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`${label} must be a positive integer.`);
    }
    return parsed;
  }

  private async fetchRegions(): Promise<RegionOption[]> {
    try {
      const result = await this.process.run("fly", ["platform", "regions", "--json"], { env: this.env });
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return STATIC_REGIONS;
      }
      const parsed = JSON.parse(result.stdout) as Array<Record<string, unknown>>;
      const options = parsed
        .map((entry) => {
          const code = String(entry.code ?? entry.Code ?? "").trim().toLowerCase();
          const name = String(entry.name ?? entry.Name ?? "").trim();
          if (code.length === 0 || name.length === 0) {
            return null;
          }
          return { code, name, area: this.regionAreaFor(code) };
        })
        .filter((entry): entry is RegionOption => entry !== null);
      return options.length > 0 ? options : STATIC_REGIONS;
    } catch {
      return STATIC_REGIONS;
    }
  }

  private async fetchVmOptions(): Promise<VmOption[]> {
    try {
      const result = await this.process.run("fly", ["platform", "vm-sizes", "--json"], { env: this.env });
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return STATIC_VM_OPTIONS;
      }
      const parsed = JSON.parse(result.stdout) as Array<Record<string, unknown>>;
      const byName = new Map<string, Record<string, unknown>>();
      parsed.forEach((entry) => {
        const name = String(entry.name ?? entry.Name ?? "").trim();
        if (name.length > 0) {
          byName.set(name, entry);
        }
      });

      const options = STATIC_VM_OPTIONS
        .filter((option) => byName.has(option.value) || option.value.startsWith("shared-cpu"))
        .map((option) => {
          const dynamic = byName.get(option.value);
          const memoryMb = Number(dynamic?.memory_mb ?? dynamic?.memoryMB ?? 0);
          const ramLabel = memoryMb >= 1024
            ? `${memoryMb / 1024} GB`
            : memoryMb > 0
              ? `${memoryMb} MB`
              : option.ramLabel;
          return {
            ...option,
            ramLabel,
          };
        });
      return options.length > 0 ? options : STATIC_VM_OPTIONS;
    } catch {
      return STATIC_VM_OPTIONS;
    }
  }

  private async validateOpenRouterKey(apiKey: string): Promise<{ ok: boolean; warning?: string }> {
    try {
      const result = await this.process.run(
        "curl",
        ["-fsSL", "--max-time", "10", OPENROUTER_KEY_API_URL, "-H", `Authorization: Bearer ${apiKey}`],
        { env: this.env }
      );
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return { ok: true };
      }

      const payload = JSON.parse(result.stdout) as { error?: unknown; data?: { is_free_tier?: boolean; usage?: number } };
      if (payload.error) {
        return { ok: false };
      }

      if (payload.data?.is_free_tier === true && Number(payload.data.usage ?? 0) === 0) {
        return {
          ok: true,
          warning: "OpenRouter shows no paid usage yet. If calls fail later, add credits at https://openrouter.ai/credits"
        };
      }
      return { ok: true };
    } catch {
      return { ok: true };
    }
  }

  private async fetchCuratedOpenRouterModels(apiKey: string, announce = this.prompts.isInteractive()): Promise<ModelOption[]> {
    if (announce) {
      this.prompts.write("Fetching available models from OpenRouter...\n");
    }

    try {
      const result = await this.process.run(
        "curl",
        ["-fsSL", "--max-time", "10", OPENROUTER_MODELS_API_URL, "-H", `Authorization: Bearer ${apiKey}`],
        { env: this.env }
      );
      if (result.exitCode !== 0 || result.stdout.trim().length === 0) {
        return this.reportDynamicModelFallback(announce);
      }

      const payload = JSON.parse(result.stdout) as { data?: Array<Record<string, unknown>> };
      const models = (payload.data ?? [])
        .map((entry) => {
          const id = String(entry.id ?? "").trim();
          const name = String(entry.name ?? "").trim();
          if (id.length === 0 || name.length === 0) {
            return null;
          }
          const rawSupportedParameters = Array.isArray(entry.supported_parameters)
            ? entry.supported_parameters
            : Array.isArray(entry.supportedParameters)
              ? entry.supportedParameters
              : [];
          const supportedParameters = rawSupportedParameters
            .map((value) => String(value ?? "").trim())
            .filter((value) => value.length > 0);
          return { id, name, supportedParameters };
        })
        .filter((entry): entry is OpenRouterModelRecord => entry !== null);

      const fullCatalog = this.buildDynamicModelOptions(models);
      if (fullCatalog.length === 0) {
        return this.reportDynamicModelFallback(announce);
      }
      this.rememberModelOptions(fullCatalog);
      return fullCatalog;
    } catch {
      return this.reportDynamicModelFallback(announce);
    }
  }

  private reportDynamicModelFallback(announce: boolean): ModelOption[] {
    if (announce) {
      this.prompts.write("I couldn't load the live OpenRouter model list.\n");
      this.prompts.write(`Browse every available model at: ${OPENROUTER_MODELS_URL}\n`);
      this.prompts.write("I'll show a starter list instead.\n\n");
    }
    return STATIC_MODEL_OPTIONS;
  }

  private buildDynamicModelOptions(models: OpenRouterModelRecord[]): ModelOption[] {
    const seen = new Set<string>();
    const options: ModelOption[] = [];

    for (const model of models) {
      if (!this.isSupportedDynamicModel(model.id) || seen.has(model.id)) {
        continue;
      }
      seen.add(model.id);
      options.push({
        value: model.id,
        label: this.cleanModelName(model.name, model.id),
        bestFor: this.inferDynamicModelNote(model),
        providerKey: this.providerKeyForModel(model.id),
        providerLabel: this.providerLabelForModel(model.id),
        supportsReasoning: model.supportedParameters.includes("reasoning"),
      });
    }

    return options;
  }

  private cleanModelName(name: string, id: string): string {
    const trimmed = name.trim();
    if (trimmed.length > 0) {
      return trimmed.replace(/^[^:]+:\s*/, "");
    }
    const [, fallback = id] = id.split("/", 2);
    return fallback;
  }

  private inferDynamicModelNote(model: OpenRouterModelRecord): string {
    const haystack = `${model.id} ${model.name}`.toLowerCase();
    if (/\bmini\b|\bhaiku\b|\bflash\b|\bnano\b|\bsmall\b/.test(haystack)) {
      return "Fast / lower cost";
    }
    if (/\bpro\b|\bopus\b|\bsonnet\b|\blarge\b|\breasoning\b/.test(haystack)) {
      return "Higher capability";
    }
    return `${this.formatProviderName(model.id)} model`;
  }

  private formatProviderName(modelId: string): string {
    return this.providerPresentation(this.providerKeyForModel(modelId)).label;
  }

  private isSupportedDynamicModel(modelId: string): boolean {
    return /^(anthropic|openai|google|meta-llama|mistralai)\//.test(modelId);
  }

  private providerKeyForModel(modelId: string): string {
    return modelId.split("/", 1)[0] ?? "other";
  }

  private providerLabelForModel(modelId: string): string {
    return this.providerPresentation(this.providerKeyForModel(modelId)).label;
  }

  private providerPresentation(providerKey: string): { label: string; description: string } {
    switch (providerKey) {
      case "anthropic":
        return { label: "Anthropic", description: "Claude models with strong quality" };
      case "openai":
        return { label: "OpenAI", description: "GPT models with broad general capability" };
      case "google":
        return { label: "Google", description: "Gemini models focused on speed" };
      case "meta-llama":
        return { label: "Meta", description: "Llama models with open weights" };
      case "mistralai":
        return { label: "Mistral", description: "Mistral models for multilingual use" };
      default:
        return {
          label: providerKey
            .split("-")
            .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
            .join(" "),
          description: "Additional models",
        };
    }
  }

  private buildProviderOptions(catalog: ModelOption[]): ProviderOption[] {
    const grouped = new Map<string, ProviderOption>();
    for (const option of catalog) {
      if (grouped.has(option.providerKey)) {
        continue;
      }
      const presentation = this.providerPresentation(option.providerKey);
      grouped.set(option.providerKey, {
        key: option.providerKey,
        label: option.providerLabel,
        description: presentation.description,
      });
    }

    return [...grouped.values()].sort((left, right) => {
      const leftIndex = PROVIDER_ORDER.indexOf(left.key);
      const rightIndex = PROVIDER_ORDER.indexOf(right.key);
      const normalizedLeft = leftIndex === -1 ? Number.MAX_SAFE_INTEGER : leftIndex;
      const normalizedRight = rightIndex === -1 ? Number.MAX_SAFE_INTEGER : rightIndex;
      if (normalizedLeft !== normalizedRight) {
        return normalizedLeft - normalizedRight;
      }
      return left.label.localeCompare(right.label);
    });
  }

  private async resolveReasoningSupport(modelId: string): Promise<ReasoningSupport> {
    const option = this.modelOptionsById.get(modelId);
    if (!option?.supportsReasoning) {
      return { supported: false, allowedEfforts: [] };
    }

    const family = this.normalizeReasoningFamily(modelId);
    const policies = await this.loadReasoningPolicies();
    const policy = family ? policies.get(family) : undefined;
    if (!policy) {
      return {
        supported: false,
        allowedEfforts: [],
        unsupportedMessage: "OpenRouter exposes reasoning controls for this model, but Hermes Agent does not yet have a tested reasoning-effort policy for it. Hermes will use the model's default reasoning behavior."
      };
    }

    return {
      supported: true,
      allowedEfforts: [...policy.allowedEfforts],
      defaultEffort: policy.defaultEffort,
    };
  }

  private describeReasoningEffort(effort: string): string {
    switch (effort) {
      case "low":
        return "Low                     Lower cost and faster responses";
      case "medium":
        return "Medium                  Balanced (recommended)";
      case "high":
        return "High                    Higher effort for harder tasks";
      default:
        return effort;
    }
  }

  private normalizeReasoningFamily(modelId: string): string | null {
    const withoutProvider = modelId.includes("/") ? modelId.split("/", 2)[1] ?? modelId : modelId;
    const normalized = withoutProvider.split(":", 2)[0] ?? withoutProvider;

    if (/^gpt-5-pro(?:[-.].+)?$/i.test(normalized)) {
      return "gpt-5-pro";
    }
    if (/^gpt-5(?:[-.].+)?$/i.test(normalized) || /^gpt-5-(?:mini|nano|codex)(?:[-.].+)?$/i.test(normalized)) {
      return "gpt-5";
    }
    return null;
  }

  private async loadReasoningPolicies(): Promise<Map<string, ReasoningPolicy>> {
    if (this.reasoningPolicies) {
      return this.reasoningPolicies;
    }

    try {
      const { readFile } = await import("node:fs/promises");
      const raw = await readFile(new URL("../../../../../data/reasoning-snapshot.json", import.meta.url), "utf8");
      const parsed = JSON.parse(raw) as {
        families?: Record<string, { allowed_efforts?: unknown; default?: unknown }>;
      };
      const policies = new Map<string, ReasoningPolicy>();
      for (const [family, value] of Object.entries(parsed.families ?? {})) {
        const allowedEfforts = Array.isArray(value.allowed_efforts)
          ? value.allowed_efforts.map((entry) => String(entry ?? "").trim()).filter((entry) => entry.length > 0)
          : [];
        const defaultEffort = String(value.default ?? "").trim();
        if (allowedEfforts.length === 0 || defaultEffort.length === 0) {
          throw new Error("invalid reasoning snapshot");
        }
        policies.set(family, { allowedEfforts, defaultEffort });
      }
      this.reasoningPolicies = policies.size > 0 ? policies : new Map(STATIC_REASONING_POLICIES);
    } catch {
      this.reasoningPolicies = new Map(STATIC_REASONING_POLICIES);
    }

    return this.reasoningPolicies;
  }

  private rememberModelOptions(options: ModelOption[]): void {
    for (const option of options) {
      this.modelLabels.set(option.value, option.label);
      this.modelOptionsById.set(option.value, option);
    }
  }

  private regionAreaFor(code: string): string {
    switch (code) {
      case "iad":
      case "ord":
      case "dfw":
      case "lax":
      case "sjc":
      case "ewr":
      case "yyz":
      case "mia":
      case "atl":
      case "den":
      case "bos":
      case "phx":
        return "Americas";
      case "ams":
      case "fra":
      case "lhr":
      case "cdg":
      case "arn":
      case "mad":
      case "waw":
      case "otp":
        return "Europe";
      case "bom":
      case "nrt":
      case "sin":
      case "hkg":
      case "del":
      case "bkk":
        return "Asia-Pacific";
      case "syd":
        return "Oceania";
      case "gru":
      case "bog":
      case "eze":
      case "scl":
      case "qro":
      case "gdl":
        return "South America";
      case "jnb":
        return "Africa";
      default:
        return "Other";
    }
  }

  private async ensureFlyAvailable(): Promise<boolean> {
    const flyPath = await this.findExecutableOnPath("fly");
    if (flyPath && await this.canRunFlyBinary(flyPath)) {
      return true;
    }

    const home = this.env.HOME ?? process.env.HOME;
    if (home) {
      const installedFlyPath = join(home, ".fly", "bin", "fly");
      if (await this.isExecutable(installedFlyPath)) {
        this.prependPath(dirname(installedFlyPath));
        if (await this.canRunFlyBinary(installedFlyPath)) {
          return true;
        }
      }
    }

    return false;
  }

  private async canRunFlyBinary(command: string): Promise<boolean> {
    try {
      const versionResult = await this.process.run(command, ["version"], { env: this.env });
      return versionResult.exitCode === 0;
    } catch {
      return false;
    }
  }

  private prependPath(dir: string): void {
    const current = this.env.PATH ?? process.env.PATH ?? "";
    const parts = current.split(":").filter(Boolean);
    if (!parts.includes(dir)) {
      this.env.PATH = `${dir}${current.length > 0 ? `:${current}` : ""}`;
    }
  }

  private async installFlyCli(): Promise<{ ok: boolean; error?: string }> {
    const platform = this.env.HERMES_FLY_PLATFORM ?? process.platform;
    const override = (this.env.HERMES_FLY_FLYCTL_INSTALL_CMD ?? "").trim();
    const command =
      override.length > 0
        ? override
        : platform === "darwin"
          ? await this.resolveMacFlyInstallCommand()
          : platform === "linux"
            ? "curl -L https://fly.io/install.sh | sh"
            : "";

    if (command.length === 0) {
      return {
        ok: false,
        error: `Automatic fly installation is unsupported on ${platform}. Install fly manually from https://fly.io/docs/flyctl/install/.`
      };
    }

    const shellResult = await this.process.run("bash", ["-c", command], { env: this.env });
    if (shellResult.exitCode !== 0) {
      const details = shellResult.stderr.trim() || shellResult.stdout.trim();
      return {
        ok: false,
        error: details.length > 0
          ? `Failed to install fly CLI automatically: ${details}`
          : "Failed to install fly CLI automatically. Install it from https://fly.io/docs/flyctl/install/ and retry."
      };
    }

    const home = this.env.HOME ?? process.env.HOME;
    if (home) {
      this.prependPath(join(home, ".fly", "bin"));
    }
    return { ok: true };
  }

  private async resolveMacFlyInstallCommand(): Promise<string> {
    if (await this.findExecutableOnPath("brew")) {
      return "brew install flyctl";
    }
    return "curl -L https://fly.io/install.sh | sh";
  }

  private async findExecutableOnPath(command: string): Promise<string | null> {
    const pathValue = this.env.PATH ?? process.env.PATH ?? "";
    for (const dir of pathValue.split(":")) {
      if (!dir) {
        continue;
      }
      const candidate = join(dir, command);
      if (await this.isExecutable(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  private async isExecutable(path: string): Promise<boolean> {
    const { access } = await import("node:fs/promises");
    try {
      await access(path, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }

  private buildDefaultAppName(): string {
    const explicit = (this.env.HERMES_FLY_DEFAULT_APP_NAME ?? "").trim();
    if (explicit.length > 0) {
      return explicit;
    }

    const uid =
      (this.env.UID ?? "").trim() || (
        typeof process.getuid === "function"
          ? String(process.getuid())
          : ""
      );
    const rawUser = (this.env.USER ?? this.env.LOGNAME ?? "agent").trim().toLowerCase();
    const user = rawUser.replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "") || "agent";
    const suffix = randomBytes(2).toString("hex");
    const parts = [DEFAULT_APP_NAME_PREFIX, user, uid, suffix].filter((part) => part.length > 0);
    let candidate = parts.join("-");
    if (candidate.length > 63) {
      const maxUserLength = Math.max(4, 63 - (DEFAULT_APP_NAME_PREFIX.length + uid.length + suffix.length + 3));
      candidate = [DEFAULT_APP_NAME_PREFIX, user.slice(0, maxUserLength), uid, suffix]
        .filter((part) => part.length > 0)
        .join("-");
    }
    return candidate;
  }

  private buildChildEnv(env?: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
    return {
      ...process.env,
      ...(env ?? {}),
      LANG: SAFE_PROCESS_LOCALE,
      LC_ALL: SAFE_PROCESS_LOCALE,
    };
  }
}
