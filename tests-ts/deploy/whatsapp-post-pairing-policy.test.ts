import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { WhatsAppPostPairingPolicy } from "../../src/contexts/deploy/domain/whatsapp-post-pairing-policy.ts";

describe("WhatsAppPostPairingPolicy", () => {
  it("offers automatic self-chat verification only for self-chat mode", () => {
    assert.equal(WhatsAppPostPairingPolicy.shouldOfferSelfChatVerification("self-chat"), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldOfferSelfChatVerification("bot"), false);
    assert.equal(WhatsAppPostPairingPolicy.shouldOfferSelfChatVerification(undefined), false);
  });

  it("keeps waiting only until the final poll attempt", () => {
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(0, 20), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(18, 20), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(19, 20), false);
  });
});
