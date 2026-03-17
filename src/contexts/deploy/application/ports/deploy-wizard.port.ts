export interface DeployConfig {
  orgSlug: string;
  appName: string;
  region: string;
  vmSize: string;
  volumeSize: number;
  provider: string;
  apiKey: string;
  authJsonB64?: string;
  model: string;
  reasoningEffort?: string;
  channel: "stable" | "preview" | "edge";
  hermesRef: string;
  botToken: string;
  telegramBotUsername?: string;
  telegramBotName?: string;
  telegramAllowedUsers?: string;
  gatewayAllowAllUsers?: boolean;
  telegramHomeChannel?: string;
}

export type SuccessfulDeploymentAction = "conclude" | "destroy";

export interface DeployWizardPort {
  checkPlatform(): Promise<{ ok: boolean; error?: string }>;
  checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean; error?: string }>;
  checkAuth(): Promise<{ ok: boolean; error?: string }>;
  checkConnectivity(): Promise<{ ok: boolean; error?: string }>;
  collectConfig(opts: { channel: "stable" | "preview" | "edge" }): Promise<DeployConfig>;
  createBuildContext(config: DeployConfig): Promise<{ buildDir: string }>;
  provisionResources(config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  runDeploy(buildDir: string, config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  postDeployCheck(appName: string): Promise<{ ok: boolean; error?: string }>;
  saveApp(appName: string, region: string): Promise<void>;
  chooseSuccessfulDeploymentAction(config: DeployConfig): Promise<SuccessfulDeploymentAction>;
  showTelegramBotDeletionGuidance(config: DeployConfig): Promise<void>;
}
