import { readCurrentApp } from "../../runtime/infrastructure/adapters/current-app-config.js";
import type { ConfigRepositoryPort } from "../application/ports/config-repository.port.js";

export class DeployConfigRepository implements ConfigRepositoryPort {
  constructor(private readonly env?: NodeJS.ProcessEnv) {}

  async readCurrentApp(): Promise<string | null> {
    return readCurrentApp({ env: this.env });
  }
}
