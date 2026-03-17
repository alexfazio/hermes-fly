export interface RemoteSessionPort {
  openAgentConsole(appName: string, hermesArgs: string[]): Promise<{ ok: boolean; error?: string }>;
  openShell(appName: string): Promise<{ ok: boolean; error?: string }>;
  execRemoteCommand(appName: string, commandArgs: string[]): Promise<{ ok: boolean; error?: string }>;
  execHermesCommand(appName: string, hermesArgs: string[]): Promise<{ ok: boolean; error?: string }>;
}
