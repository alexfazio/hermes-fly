export interface ResumeChecksPort {
  fetchStatus(appName: string): Promise<{ ok: boolean; region: string | null }>;
  checkMachineRunning(appName: string): Promise<boolean>;
  saveApp(appName: string, region: string): Promise<void>;
}
