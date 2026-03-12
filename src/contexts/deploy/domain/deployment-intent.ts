export type DeployChannel = "stable" | "preview" | "edge";

export interface DeploymentIntentInput {
  appName: string;
  region: string;
  vmSize: string;
  provider: string;
  model: string;
  channel?: DeployChannel;
}

const CHANNELS: readonly DeployChannel[] = ["stable", "preview", "edge"];

export class DeploymentIntent {
  readonly appName: string;
  readonly region: string;
  readonly vmSize: string;
  readonly provider: string;
  readonly model: string;
  readonly channel: DeployChannel;

  private constructor(input: {
    appName: string;
    region: string;
    vmSize: string;
    provider: string;
    model: string;
    channel: DeployChannel;
  }) {
    this.appName = input.appName;
    this.region = input.region;
    this.vmSize = input.vmSize;
    this.provider = input.provider;
    this.model = input.model;
    this.channel = input.channel;
  }

  static create(input: DeploymentIntentInput): DeploymentIntent {
    const appName = input.appName.trim();
    if (appName.length === 0) {
      throw new Error("DeploymentIntent.appName must be non-empty");
    }

    const region = input.region.trim();
    if (region.length === 0) {
      throw new Error("DeploymentIntent.region must be non-empty");
    }

    const vmSize = input.vmSize.trim();
    if (vmSize.length === 0) {
      throw new Error("DeploymentIntent.vmSize must be non-empty");
    }

    const provider = input.provider.trim();
    if (provider.length === 0) {
      throw new Error("DeploymentIntent.provider must be non-empty");
    }

    const model = input.model.trim();
    if (model.length === 0) {
      throw new Error("DeploymentIntent.model must be non-empty");
    }

    const channel = input.channel ?? "stable";
    if (!CHANNELS.includes(channel)) {
      throw new Error("DeploymentIntent.channel must be one of stable|preview|edge");
    }

    return new DeploymentIntent({
      appName,
      region,
      vmSize,
      provider,
      model,
      channel,
    });
  }
}
