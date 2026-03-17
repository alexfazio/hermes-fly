import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { describe, it } from "node:test";

import { DiscordBotAuthAdapter } from "../../src/contexts/deploy/infrastructure/adapters/discord-bot-auth.ts";

class MockDiscordClient extends EventEmitter {
  public user: { id?: string; username?: string; tag?: string } | null = null;
  public destroyed = false;
  public inviteOptions: unknown[] = [];

  constructor(
    private readonly behavior:
      | { kind: "success"; id: string; username: string; tag?: string; inviteUrl: string }
      | { kind: "error"; error: Error }
  ) {
    super();
  }

  async login(_token: string): Promise<void> {
    if (this.behavior.kind === "error") {
      throw this.behavior.error;
    }
    this.user = {
      id: this.behavior.id,
      username: this.behavior.username,
      tag: this.behavior.tag,
    };
    queueMicrotask(() => this.emit("clientReady", this));
  }

  destroy(): void {
    this.destroyed = true;
  }

  generateInvite(options: unknown): string {
    this.inviteOptions.push(options);
    if (this.behavior.kind === "error") {
      throw new Error("generateInvite should not be called for errors");
    }
    return this.behavior.inviteUrl;
  }
}

describe("DiscordBotAuthAdapter", () => {
  it("validates a bot token with discord.js and returns the bot identity plus invite url", async () => {
    const client = new MockDiscordClient({
      kind: "success",
      id: "123456789012345678",
      username: "hermes-discord-bot",
      tag: "hermes-discord-bot#0001",
      inviteUrl: "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands",
    });
    const adapter = new DiscordBotAuthAdapter(() => client, 500);

    const result = await adapter.validateBotToken("discord-live-token");

    assert.deepEqual(result, {
      ok: true,
      identity: {
        applicationId: "123456789012345678",
        username: "hermes-discord-bot",
        tag: "hermes-discord-bot#0001",
        inviteUrl: "https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands",
      },
    });
    assert.equal(client.destroyed, true);
    assert.equal(client.inviteOptions.length, 1);
  });

  it("classifies invalid token failures clearly", async () => {
    const adapter = new DiscordBotAuthAdapter(
      () => new MockDiscordClient({
        kind: "error",
        error: new Error("TokenInvalid: An invalid token was provided."),
      }),
      500
    );

    const result = await adapter.validateBotToken("bad-token");

    assert.equal(result.ok, false);
    assert.equal(result.reason, "invalid_token");
    assert.match(result.error ?? "", /invalid token/i);
  });
});

