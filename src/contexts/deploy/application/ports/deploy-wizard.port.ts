export interface DeployConfig {
  appName: string;
  region: string;
  vmSize: string;
  volumeSize: number;
  apiKey: string;
  model: string;
  channel: "stable" | "preview" | "edge";
  hermesRef: string;
  botToken: string;
}

export interface DeployWizardPort {
  checkPlatform(): Promise<{ ok: boolean; error?: string }>;
  checkPrerequisites(opts: { autoInstall: boolean }): Promise<{ ok: boolean; missing?: string; autoInstallDisabled?: boolean }>;
  checkAuth(): Promise<{ ok: boolean; error?: string }>;
  checkConnectivity(): Promise<{ ok: boolean; error?: string }>;
  collectConfig(opts: { channel: "stable" | "preview" | "edge" }): Promise<DeployConfig>;
  createBuildContext(config: DeployConfig): Promise<{ buildDir: string }>;
  provisionResources(config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  runDeploy(buildDir: string, config: DeployConfig): Promise<{ ok: boolean; error?: string }>;
  postDeployCheck(appName: string): Promise<{ ok: boolean; error?: string }>;
  saveApp(appName: string, region: string): Promise<void>;
}
