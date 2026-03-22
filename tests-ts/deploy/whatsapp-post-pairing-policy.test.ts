import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { WhatsAppPostPairingPolicy } from "../../src/contexts/deploy/domain/whatsapp-post-pairing-policy.ts";

describe("WhatsAppPostPairingPolicy", () => {
  it("runs automatic self-chat verification only for self-chat mode", () => {
    assert.equal(WhatsAppPostPairingPolicy.shouldAutomaticallyVerifySelfChat("self-chat"), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldAutomaticallyVerifySelfChat("bot"), false);
    assert.equal(WhatsAppPostPairingPolicy.shouldAutomaticallyVerifySelfChat(undefined), false);
  });

  it("keeps waiting only until the final poll attempt", () => {
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(0, 20), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(18, 20), true);
    assert.equal(WhatsAppPostPairingPolicy.shouldPauseAfterAttempt(19, 20), false);
  });
});
