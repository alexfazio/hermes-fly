import type { DeploymentPlan } from "../../domain/deployment-plan.js";

export interface DeploymentPlanWriterPort {
  write(plan: DeploymentPlan): Promise<void>;
}
