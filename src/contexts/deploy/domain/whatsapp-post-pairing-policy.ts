export type WhatsAppPostPairingMode = "bot" | "self-chat";

export class WhatsAppPostPairingPolicy {
  static readonly bridgeReconnectAttemptLimit = 20;
  static readonly selfChatVerificationAttemptLimit = 20;
  static readonly pollDelayMs = 1_500;

  static shouldAutomaticallyVerifySelfChat(mode?: WhatsAppPostPairingMode): boolean {
    return mode === "self-chat";
  }

  static shouldPauseAfterAttempt(attempt: number, attemptLimit: number): boolean {
    return attempt < attemptLimit - 1;
  }
}
