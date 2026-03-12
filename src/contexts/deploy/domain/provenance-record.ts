import type { DeployChannel } from "./deployment-intent.js";

export interface ProvenanceRecordInput {
  hermesFlyVersion: string;
  hermesAgentRef: string;
  compatPolicyVersion: string;
  reasoningEffort: string;
  llmProvider: string;
  llmModel: string;
  deployChannel: DeployChannel;
  writtenAt: string;
}

const CHANNELS: readonly DeployChannel[] = ["stable", "preview", "edge"];

export class ProvenanceRecord {
  readonly hermesFlyVersion: string;
  readonly hermesAgentRef: string;
  readonly compatPolicyVersion: string;
  readonly reasoningEffort: string;
  readonly llmProvider: string;
  readonly llmModel: string;
  readonly deployChannel: DeployChannel;
  readonly writtenAt: string;

  private constructor(input: ProvenanceRecordInput) {
    this.hermesFlyVersion = input.hermesFlyVersion;
    this.hermesAgentRef = input.hermesAgentRef;
    this.compatPolicyVersion = input.compatPolicyVersion;
    this.reasoningEffort = input.reasoningEffort;
    this.llmProvider = input.llmProvider;
    this.llmModel = input.llmModel;
    this.deployChannel = input.deployChannel;
    this.writtenAt = input.writtenAt;
  }

  static create(input: ProvenanceRecordInput): ProvenanceRecord {
    const hermesFlyVersion = input.hermesFlyVersion.trim();
    if (hermesFlyVersion.length === 0) {
      throw new Error("ProvenanceRecord.hermesFlyVersion must be non-empty");
    }

    const hermesAgentRef = input.hermesAgentRef.trim();
    if (hermesAgentRef.length === 0) {
      throw new Error("ProvenanceRecord.hermesAgentRef must be non-empty");
    }

    const compatPolicyVersion = input.compatPolicyVersion.trim();
    if (compatPolicyVersion.length === 0) {
      throw new Error("ProvenanceRecord.compatPolicyVersion must be non-empty");
    }

    const reasoningEffort = input.reasoningEffort.trim();
    if (reasoningEffort.length === 0) {
      throw new Error("ProvenanceRecord.reasoningEffort must be non-empty");
    }

    const llmProvider = input.llmProvider.trim();
    if (llmProvider.length === 0) {
      throw new Error("ProvenanceRecord.llmProvider must be non-empty");
    }

    const llmModel = input.llmModel.trim();
    if (llmModel.length === 0) {
      throw new Error("ProvenanceRecord.llmModel must be non-empty");
    }

    const writtenAt = input.writtenAt.trim();
    if (writtenAt.length === 0) {
      throw new Error("ProvenanceRecord.writtenAt must be non-empty");
    }

    if (!CHANNELS.includes(input.deployChannel)) {
      throw new Error("ProvenanceRecord.deployChannel must be one of stable|preview|edge");
    }

    return new ProvenanceRecord({
      hermesFlyVersion,
      hermesAgentRef,
      compatPolicyVersion,
      reasoningEffort,
      llmProvider,
      llmModel,
      deployChannel: input.deployChannel,
      writtenAt,
    });
  }
}
