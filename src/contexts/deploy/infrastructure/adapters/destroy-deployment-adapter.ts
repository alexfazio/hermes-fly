import type { PostDeployCleanupPort, PostDeployCleanupResult } from "../../application/ports/post-deploy-cleanup.port.js";
import { DestroyDeploymentUseCase } from "../../../release/application/use-cases/destroy-deployment.js";

export class DestroyDeploymentAdapter implements PostDeployCleanupPort {
  constructor(private readonly useCase: DestroyDeploymentUseCase) {}

  async destroyDeployment(
    appName: string,
    io: {
      stdout: { write: (s: string) => void };
      stderr: { write: (s: string) => void };
    }
  ): Promise<PostDeployCleanupResult> {
    const result = await this.useCase.execute(appName, io);
    if (result.kind === "ok" || result.kind === "already_absent") {
      return { ok: true };
    }
    return { ok: false, error: result.error };
  }
}
