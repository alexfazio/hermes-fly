import type { FlyctlPort } from "../../../../adapters/flyctl.js";
import type { StatusReaderPort, StatusReadResult } from "../../application/ports/status-reader.port.js";

export class FlyStatusReader implements StatusReaderPort {
  constructor(private readonly flyctl: FlyctlPort) {}

  async getStatus(appName: string): Promise<StatusReadResult> {
    const result = await this.flyctl.getAppStatus(appName);

    if (!result.ok) {
      return { kind: "error", message: result.error };
    }

    return {
      kind: "ok",
      details: {
        appName: result.appName,
        status: result.status ?? "unknown",
        machine: result.machineState ?? "unknown",
        region: result.region ?? "unknown",
        hostname: result.hostname
      }
    };
  }
}
