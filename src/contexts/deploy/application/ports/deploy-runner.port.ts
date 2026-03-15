export interface DeployRunnerPort {
  createApp(appName: string, region: string): Promise<{ ok: boolean; error?: string }>;
  createVolume(appName: string, region: string, sizeGb: number): Promise<{ ok: boolean; error?: string }>;
  setSecrets(appName: string, secrets: Record<string, string>): Promise<{ ok: boolean; error?: string }>;
}
