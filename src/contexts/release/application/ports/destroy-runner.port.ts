export type DestroyAppResult =
  | { ok: true }
  | { ok: false; reason: "not_found" | "failed"; error?: string };

export interface DestroyRunnerPort {
  destroyApp(appName: string): Promise<DestroyAppResult>;
  cleanupVolumes(appName: string): Promise<void>;
  telegramLogout(appName: string): Promise<void>;
  removeConfig(appName: string): Promise<void>;
}
