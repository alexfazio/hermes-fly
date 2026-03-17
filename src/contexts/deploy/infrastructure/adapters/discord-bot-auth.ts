import { once } from "node:events";
import {
  Client,
  Events,
  GatewayIntentBits,
  OAuth2Scopes,
  PermissionFlagsBits,
  type ClientEvents,
} from "discord.js";

export type DiscordBotIdentity = {
  applicationId: string;
  username: string;
  tag?: string;
  inviteUrl: string;
};

export type DiscordBotValidationResult =
  | { ok: true; identity: DiscordBotIdentity }
  | { ok: false; reason: "invalid_token" | "timeout" | "network" | "unknown"; error?: string };

export interface DiscordBotAuthPort {
  validateBotToken(token: string): Promise<DiscordBotValidationResult>;
}

type DiscordClientLike = {
  login(token: string): Promise<unknown>;
  destroy(): void;
  user?: {
    id?: string;
    username?: string;
    tag?: string;
  } | null;
  generateInvite(options: unknown): string;
  once(event: string, listener: (...args: unknown[]) => void): unknown;
  off?(event: string, listener: (...args: unknown[]) => void): unknown;
};

type DiscordClientFactory = () => DiscordClientLike;

const DEFAULT_LOGIN_TIMEOUT_MS = 10_000;

export class DiscordBotAuthAdapter implements DiscordBotAuthPort {
  constructor(
    private readonly clientFactory: DiscordClientFactory = () =>
      new Client({ intents: [GatewayIntentBits.Guilds] }),
    private readonly loginTimeoutMs = DEFAULT_LOGIN_TIMEOUT_MS
  ) {}

  async validateBotToken(token: string): Promise<DiscordBotValidationResult> {
    const client = this.clientFactory();
    try {
      const readyPromise = once(client as unknown as NodeJS.EventEmitter, Events.ClientReady as keyof ClientEvents);
      await client.login(token);
      await this.awaitReady(readyPromise);

      const applicationId = String(client.user?.id ?? "").trim();
      const username = String(client.user?.username ?? "").trim();
      const tag = String(client.user?.tag ?? "").trim();
      if (!/^[0-9]+$/.test(applicationId) || username.length === 0) {
        return { ok: false, reason: "unknown", error: "Discord login succeeded, but the bot identity was incomplete." };
      }

      const inviteUrl = client.generateInvite({
        scopes: [OAuth2Scopes.Bot, OAuth2Scopes.ApplicationsCommands],
        permissions: [
          PermissionFlagsBits.ViewChannel,
          PermissionFlagsBits.SendMessages,
          PermissionFlagsBits.ReadMessageHistory,
          PermissionFlagsBits.AttachFiles,
          PermissionFlagsBits.UseApplicationCommands,
        ],
      });

      return {
        ok: true,
        identity: {
          applicationId,
          username,
          tag: tag.length > 0 ? tag : undefined,
          inviteUrl,
        },
      };
    } catch (error) {
      const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
      return {
        ok: false,
        reason: classifyDiscordLoginError(message),
        error: message,
      };
    } finally {
      client.destroy();
    }
  }

  private async awaitReady(readyPromise: Promise<unknown>): Promise<void> {
    await Promise.race([
      readyPromise.then(() => undefined),
      new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("Discord client login timed out.")), this.loginTimeoutMs);
      }),
    ]);
  }
}

function classifyDiscordLoginError(message: string): "invalid_token" | "timeout" | "network" | "unknown" {
  const lowered = message.toLowerCase();
  if (lowered.includes("timed out")) {
    return "timeout";
  }
  if (
    lowered.includes("tokeninvalid")
    || lowered.includes("invalid token")
    || lowered.includes("used disallowed intents")
    || lowered.includes("unauthorized")
    || lowered.includes("401")
  ) {
    return "invalid_token";
  }
  if (
    lowered.includes("enotfound")
    || lowered.includes("econnreset")
    || lowered.includes("network")
    || lowered.includes("socket")
  ) {
    return "network";
  }
  return "unknown";
}

