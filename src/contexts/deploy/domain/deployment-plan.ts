import type { DeploymentIntent } from "./deployment-intent.js";

export interface DeploymentPlanInput {
  intent: DeploymentIntent;
  hermesAgentRef: string;
  compatPolicyVersion: string;
  createdAtIso: string;
}

const COMPAT_POLICY_VERSION = /^v[0-9]+\.[0-9]+\.[0-9]+$/;
const ISO_8601_UTC_MILLIS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export class DeploymentPlan {
  readonly intent: DeploymentIntent;
  readonly hermesAgentRef: string;
  readonly compatPolicyVersion: string;
  readonly createdAtIso: string;

  private constructor(input: DeploymentPlanInput) {
    this.intent = input.intent;
    this.hermesAgentRef = input.hermesAgentRef;
    this.compatPolicyVersion = input.compatPolicyVersion;
    this.createdAtIso = input.createdAtIso;
  }

  static create(input: DeploymentPlanInput): DeploymentPlan {
    const hermesAgentRef = input.hermesAgentRef.trim();
    if (hermesAgentRef.length === 0) {
      throw new Error("DeploymentPlan.hermesAgentRef must be non-empty");
    }

    const compatPolicyVersion = input.compatPolicyVersion.trim();
    if (!COMPAT_POLICY_VERSION.test(compatPolicyVersion)) {
      throw new Error("DeploymentPlan.compatPolicyVersion must be semver with v prefix");
    }

    const createdAtIso = input.createdAtIso.trim();
    if (createdAtIso.length === 0 || !ISO_8601_UTC_MILLIS.test(createdAtIso)) {
      throw new Error("DeploymentPlan.createdAtIso must be valid ISO-8601");
    }

    const parsedDate = new Date(createdAtIso);
    if (Number.isNaN(parsedDate.getTime()) || parsedDate.toISOString() !== createdAtIso) {
      throw new Error("DeploymentPlan.createdAtIso must be valid ISO-8601");
    }

    if (input.intent.channel === "stable" && hermesAgentRef === "main") {
      throw new Error("DeploymentPlan.hermesAgentRef must be pinned for stable channel");
    }

    return new DeploymentPlan({
      intent: input.intent,
      hermesAgentRef,
      compatPolicyVersion,
      createdAtIso,
    });
  }
}
