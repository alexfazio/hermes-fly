export interface DeployConfig {
  orgSlug: string;
  appName: string;
  region: string;
  vmSize: string;
  volumeSize: number;
  provider: string;
  apiKey: string;
  apiBaseUrl?: string;
  authJsonB64?: string;
  anthropicOauthJsonB64?: string;
  model: string;
  reasoningEffort?: string;
  sttProvider?: string;
  sttModel?: string;
  channel: "stable" | "preview" | "edge";
  hermesRef: string;
  botToken: string;
  telegramBotUsername?: string;
  telegramBotName?: string;
  telegramAllowedUsers?: string;
  gatewayAllowAllUsers?: boolean;
  telegramHomeChannel?: string;
  messagingPlatforms?: string[];
  discordBotToken?: string;
  discordApplicationId?: string;
  discordBotUsername?: string;
  discordAllowedUsers?: string;
  discordUsePairing?: boolean;
  slackBotToken?: string;
  slackAppToken?: string;
  slackTeamName?: string;
  slackBotUserId?: string;
  slackAllowedUsers?: string;
  slackUsePairing?: boolean;
  whatsappEnabled?: boolean;
  whatsappMode?: "bot" | "self-chat";
  whatsappAllowedUsers?: string;
  whatsappUsePairing?: boolean;
  whatsappCompleteAccessDuringSetup?: boolean;
  whatsappSessionConfirmed?: boolean;
  whatsappTakeoverAppNames?: string[];
}

export interface FinalizeMessagingSetupResult {
  whatsappSessionConfirmed?: boolean;
}

export type SuccessfulDeploymentAction = "conclude" | "destroy";

export interface ExistingAppConfig {
  region: string;
  vmSize: string;
  volumeSize: number;
}

export interface DeployWizardPort {
  checkPlatform(): Promise<{ ok: boolean; error?: string }>;
  checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean; error?: string }>;
  checkAuth(): Promise<{ ok: boolean; error?: string }>;
  checkConnectivity(): Promise<{ ok: boolean; error?: string }>;
  collectConfig(opts: { channel: "stable" | "preview" | "edge" }): Promise<DeployConfig>;
  fetchExistingConfig(appName: string): Promise<ExistingAppConfig | null>;
  promptUpdateConfigChoice(existing: ExistingAppConfig): Promise<{ keep: boolean; config?: DeployConfig }>;
  createBuildContext(config: DeployConfig, opts?: { update?: boolean }): Promise<{ buildDir: string }>;
  provisionResources(config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  runDeploy(buildDir: string, config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  postDeployCheck(appName: string): Promise<{ ok: boolean; error?: string }>;
  saveApp(config: DeployConfig): Promise<void>;
  finalizeMessagingSetup(
    config: DeployConfig,
    stdout: { write: (s: string) => void },
    stderr: { write: (s: string) => void }
  ): Promise<FinalizeMessagingSetupResult>;
  chooseSuccessfulDeploymentAction(config: DeployConfig): Promise<SuccessfulDeploymentAction>;
  showTelegramBotDeletionGuidance(config: DeployConfig): Promise<void>;
}
