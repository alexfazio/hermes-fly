export interface DestroyRunnerPort {
  destroyApp(appName: string): Promise<{ ok: boolean }>;
  cleanupVolumes(appName: string): Promise<void>;
  telegramLogout(appName: string): Promise<void>;
  removeConfig(appName: string): Promise<void>;
}
