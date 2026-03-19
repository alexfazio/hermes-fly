# Telegram "Only Me" User ID Autodiscovery Plan

**Date**: 2026-03-19
**Status**: READY
**Priority**: HIGH
**Scope**: Deploy wizard and Telegram messaging setup only

---

## Objective

Remove the extra "go ask another bot for your Telegram user ID" step when the user selects `Only me`.

The wizard should discover the current user's Telegram numeric ID directly from the bot interaction flow whenever possible, then use that value as the allowlist entry without asking the user to leave the product.

## Problem

The current flow says:

1. choose `Only me`
2. open `@userinfobot`
3. copy the numeric ID back into the wizard

That adds friction and pushes users through a third-party bot for information we can infer ourselves from Telegram updates. It is a poor fit for the otherwise guided installer and deploy experience.

## Desired Outcome

When the user selects `Only me`, hermes-fly should:

1. prompt the user to send `/start` to their bot
2. fetch the most recent Telegram update for that bot
3. extract the sender's numeric user ID
4. confirm the discovered ID with the user
5. persist it as the Telegram allowlist entry

If no update is available, the wizard should fall back to a manual entry path with clear instructions.

## Domain Design

Boundaries:

- `messaging` domain owns the concept of a Telegram allowed-user identity
- the deploy wizard application layer orchestrates discovery and confirmation
- infrastructure adapters talk to Telegram APIs and translate raw updates into domain values

Suggested primitives:

- `TelegramUserId`
- `TelegramAccessPolicy`
- `TelegramIdentityDiscoveryResult`

Suggested application use case:

- `discoverTelegramOnlyMeIdentity()`

That use case should return one of:

- `discovered(userId, displayName?)`
- `manual_entry_required(reason)`
- `discovery_failed(reason)`

The presenter layer should decide how to render prompts and fallback copy. Telegram API payload parsing should stay outside the domain layer.

## TDD Plan

1. Add domain tests for `TelegramUserId` validation and `TelegramIdentityDiscoveryResult`.
2. Add application tests for the `Only me` branch:
   - successful auto-discovery from a recent `/start` update
   - no matching update available
   - malformed Telegram payload
3. Add runtime or wizard interaction tests that prove the manual fallback still works.
4. Implement the adapter and orchestration only after the tests define the expected behavior.

## Acceptance Criteria

- Selecting `Only me` no longer instructs the user to visit `@userinfobot` by default.
- The wizard can derive the user's Telegram numeric ID from bot updates when the user has already messaged the bot.
- The flow confirms the discovered identity before saving it.
- If discovery is unavailable, the fallback asks for manual entry without blocking the rest of the setup.
- Existing `Specific people` and `Anyone` flows are unchanged.

## Risks

- Telegram updates may contain older messages from a different user if the bot is shared.
- Bots that have pending updates disabled or already-consumed updates may have no discoverable identity.
- The UX must avoid implying that auto-discovery is guaranteed.

## Out of Scope

- Automatic discovery for multiple allowed users
- Discord or WhatsApp identity discovery
- Changes to Telegram bot provisioning outside the existing deploy wizard flow
