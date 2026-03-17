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
    if (result.kind === "ok") {
      return { ok: true };
    }
    if (result.kind === "not_found") {
      return { ok: false, notFound: true };
    }
    return { ok: false, error: result.error };
  }
}
