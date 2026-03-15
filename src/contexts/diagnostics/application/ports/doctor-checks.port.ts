export interface DoctorChecksPort {
  checkAppExists(appName: string): Promise<boolean>;
  checkMachineRunning(appName: string): Promise<boolean>;
  checkVolumesMounted(appName: string): Promise<boolean>;
  checkSecretsSet(appName: string): Promise<boolean>;
  checkHermesProcess(appName: string): Promise<boolean>;
  checkGatewayHealth(appName: string): Promise<boolean>;
  checkApiConnectivity(appName: string): Promise<boolean>;
  checkDrift(appName: string): Promise<boolean | "unverified">;
}
