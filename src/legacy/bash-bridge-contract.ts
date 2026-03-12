export type LegacyFallbackReason = "ts_unavailable" | "fallback_signal" | "runtime_error";

export interface LegacyCommandInvocation {
  command: string;
  args: string[];
  fallbackReason: LegacyFallbackReason;
}

export interface LegacyCommandResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface LegacyBashBridge {
  invoke(command: LegacyCommandInvocation): Promise<LegacyCommandResult>;
}
