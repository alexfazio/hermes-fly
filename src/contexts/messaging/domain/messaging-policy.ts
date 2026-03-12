export type MessagingPolicyMode = "only_me" | "specific_users" | "anyone";

const MODES: readonly MessagingPolicyMode[] = ["only_me", "specific_users", "anyone"];

export class MessagingPolicy {
  readonly mode: MessagingPolicyMode;
  readonly allowedUsers: number[];

  private constructor(mode: MessagingPolicyMode, allowedUsers: number[]) {
    this.mode = mode;
    this.allowedUsers = allowedUsers;
  }

  static create(mode: MessagingPolicyMode, allowedUsers: number[]): MessagingPolicy {
    if (!MODES.includes(mode)) {
      throw new Error("MessagingPolicy.mode must be only_me|specific_users|anyone");
    }

    const areNumericUserIds =
      Array.isArray(allowedUsers) &&
      allowedUsers.every((userId) => Number.isInteger(userId) && Number.isFinite(userId));

    if (mode === "only_me") {
      if (!areNumericUserIds || allowedUsers.length !== 1) {
        throw new Error("MessagingPolicy.only_me requires exactly one numeric user id");
      }
      return new MessagingPolicy(mode, [...allowedUsers]);
    }

    if (mode === "specific_users") {
      const uniqueCount = new Set(allowedUsers).size;
      if (!areNumericUserIds || allowedUsers.length < 1 || uniqueCount !== allowedUsers.length) {
        throw new Error("MessagingPolicy.specific_users requires one or more numeric user ids");
      }
      return new MessagingPolicy(mode, [...allowedUsers]);
    }

    if (allowedUsers.length > 0) {
      throw new Error("MessagingPolicy.anyone must not include user ids");
    }

    return new MessagingPolicy(mode, []);
  }
}
