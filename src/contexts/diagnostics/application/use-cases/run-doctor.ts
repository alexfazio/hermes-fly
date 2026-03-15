import type { DoctorChecksPort } from "../ports/doctor-checks.port.js";

export interface DoctorCheckResult {
  key: string;
  pass: boolean;
  message: string;
}

export interface DoctorResult {
  checks: DoctorCheckResult[];
  passCount: number;
  failCount: number;
  allPassed: boolean;
}

export class RunDoctorUseCase {
  constructor(private readonly checks: DoctorChecksPort) {}

  async execute(appName: string): Promise<DoctorResult> {
    const results: DoctorCheckResult[] = [];
    let passCount = 0;
    let failCount = 0;

    // Check 1: App exists
    const appExists = await this.checks.checkAppExists(appName);
    if (appExists) {
      results.push({ key: "app", pass: true, message: `App '${appName}' found` });
      passCount++;
    } else {
      results.push({ key: "app", pass: false, message: `App '${appName}' not found. Create with: hermes-fly deploy` });
      failCount++;
      // Early exit — remaining checks depend on app existence
      return { checks: results, passCount, failCount, allPassed: false };
    }

    // Check 2: Machine running
    const machineRunning = await this.checks.checkMachineRunning(appName);
    if (machineRunning) {
      results.push({ key: "machine", pass: true, message: "Machine is running" });
      passCount++;
    } else {
      results.push({ key: "machine", pass: false, message: `Machine not running. Start with: fly machine start -a ${appName}` });
      failCount++;
    }

    // Check 3: Volumes mounted
    const volumesMounted = await this.checks.checkVolumesMounted(appName);
    if (volumesMounted) {
      results.push({ key: "volumes", pass: true, message: "Volumes attached" });
      passCount++;
    } else {
      results.push({ key: "volumes", pass: false, message: `No volumes found. Create with: fly volumes create -a ${appName}` });
      failCount++;
    }

    // Check 4: Secrets set
    const secretsSet = await this.checks.checkSecretsSet(appName);
    if (secretsSet) {
      results.push({ key: "secrets", pass: true, message: "Required secrets are set" });
      passCount++;
    } else {
      results.push({ key: "secrets", pass: false, message: `Secrets missing. Set with: fly secrets set OPENROUTER_API_KEY=xxx -a ${appName}` });
      failCount++;
    }

    // Check 5: Hermes process
    const hermesProcess = await this.checks.checkHermesProcess(appName);
    if (hermesProcess) {
      results.push({ key: "hermes", pass: true, message: "Hermes process detected" });
      passCount++;
    } else {
      results.push({ key: "hermes", pass: false, message: "Hermes process not found in status" });
      failCount++;
    }

    // Check 6: Gateway health
    const gatewayHealth = await this.checks.checkGatewayHealth(appName);
    if (gatewayHealth) {
      results.push({ key: "gateway", pass: true, message: "Gateway is responding" });
      passCount++;
    } else {
      results.push({ key: "gateway", pass: false, message: `Gateway not responding at https://${appName}.fly.dev` });
      failCount++;
    }

    // Check 7: API connectivity
    const apiConnectivity = await this.checks.checkApiConnectivity(appName);
    if (apiConnectivity) {
      results.push({ key: "api", pass: true, message: "LLM API is reachable" });
      passCount++;
    } else {
      results.push({ key: "api", pass: false, message: "LLM API unreachable at https://openrouter.ai" });
      failCount++;
    }

    // Check 8: Drift detection
    const driftResult = await this.checks.checkDrift(appName);
    if (driftResult === "unverified") {
      results.push({ key: "drift", pass: true, message: "Deploy provenance unverified (runtime manifest unavailable)" });
      passCount++;
    } else if (driftResult) {
      results.push({ key: "drift", pass: true, message: "Deploy provenance consistent" });
      passCount++;
    } else {
      results.push({ key: "drift", pass: false, message: "Deploy drift detected — run 'hermes-fly deploy' to refresh" });
      failCount++;
    }

    return {
      checks: results,
      passCount,
      failCount,
      allPassed: failCount === 0
    };
  }
}
