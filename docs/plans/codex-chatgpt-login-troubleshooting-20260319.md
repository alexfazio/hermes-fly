# Codex ChatGPT Login Troubleshooting Guidance Plan

**Date**: 2026-03-19
**Status**: READY
**Priority**: MEDIUM
**Scope**: Wizard guidance and troubleshooting copy only

---

## Objective

Add a clear troubleshooting hint for users who cannot connect Codex to ChatGPT during setup.

The guidance should point users to the ChatGPT security settings page and explain the two toggles that may unblock the sign-in flow:

- `Codex CLI`
- `Enable device code authorization for Codex`

## Problem

When Codex sign-in fails, the current wizard does not give the user a direct next step. The missing guidance forces people to search for the relevant ChatGPT settings manually and creates avoidable support churn.

## Desired Outcome

If the wizard detects a Codex authentication problem, or if the user asks for help during that step, it should show:

- the settings URL: <https://chatgpt.com/#settings/Security>
- a short explanation of what to enable
- a brief warning that device code authorization should be used carefully and device codes must never be shared

## Domain Design

Boundaries:

- authentication state remains owned by the existing Codex/OpenAI integration boundary
- the setup wizard application layer decides when troubleshooting guidance is relevant
- presenter copy owns the exact wording and link rendering

This is a guidance feature, not a new auth implementation. It should not change token storage, login transport, or provider selection logic.

## TDD Plan

1. Add application tests proving troubleshooting guidance is attached to the relevant auth-failure states.
2. Add runtime interaction tests for the wizard output so the URL and toggle names appear exactly when expected.
3. Verify the success path does not show this extra guidance.

## Acceptance Criteria

- Users hitting Codex login trouble see the security settings URL in the wizard.
- The copy explicitly mentions `Codex CLI`.
- The copy explicitly mentions `Enable device code authorization for Codex`.
- The copy warns users not to share device codes.
- Successful auth flows remain unchanged.

## Risks

- The settings page structure or labels may change upstream.
- Over-eager troubleshooting copy could show up in situations unrelated to ChatGPT auth.

## Out of Scope

- Automating ChatGPT settings changes
- Browser automation
- New login methods or fallback auth transports
