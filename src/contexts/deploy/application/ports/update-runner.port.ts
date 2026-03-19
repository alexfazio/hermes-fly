/**
 * Port interface for updating existing deployments.
 * Extends DeployRunnerPort but skips resource creation (app, volume already exist).
 */
export interface UpdateRunnerPort {
  checkAppExists(appName: string): Promise<{ exists: boolean; error?: string }>;
  runUpdate(buildDir: string, appName: string): Promise<{ ok: boolean; error?: string }>;
}
