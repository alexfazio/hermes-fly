import type {
  LegacyCommandInvocation,
  LegacyCommandResult,
} from "../../../../legacy/bash-bridge-contract.js";

export interface LegacyCommandRunnerPort {
  run(invocation: LegacyCommandInvocation): Promise<LegacyCommandResult>;
}
