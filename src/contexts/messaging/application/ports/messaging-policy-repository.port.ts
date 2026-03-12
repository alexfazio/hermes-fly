import type { MessagingPolicy } from "../../domain/messaging-policy.js";

export interface MessagingPolicyRepositoryPort {
  save(policy: MessagingPolicy): Promise<void>;
  load(): Promise<MessagingPolicy | null>;
}
