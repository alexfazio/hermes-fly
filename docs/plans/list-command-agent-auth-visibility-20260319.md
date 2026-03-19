# List Command Agent Authentication Visibility Plan

**Date**: 2026-03-19
**Status**: READY
**Priority**: MEDIUM
**Scope**: TypeScript Commander.js list and status-style read models only

---

## Objective

Expose how each deployed Hermes agent was configured for model access so the operator can distinguish setups such as:

- OpenAI OAuth
- OpenAI API key
- OpenRouter API key
- custom base URL plus API key
- unknown or incomplete configuration

## Problem

The current list output reports deployment presence but not the effective auth mode behind the agent. That makes it harder to audit existing apps, debug failed sessions, and compare environments before changing credentials.

## Desired Outcome

`hermes-fly list` should include a concise configuration summary for each app, focused on the authentication mechanism actually in use rather than dumping raw secrets or environment values.

Example summary labels:

- `OpenAI OAuth`
- `OpenAI API key`
- `OpenRouter API key`
- `Custom provider`
- `Not configured`

## Domain Design

Boundaries:

- a read-model domain object should describe agent auth mode without exposing secrets
- application services should map deployment configuration into that read model
- infrastructure adapters may inspect Fly secrets, config files, or runtime metadata, but should not leak raw secret values upward

Suggested primitives:

- `AgentAuthMode`
- `AgentConfigurationSummary`
- `DeploymentConfigurationSnapshot`

Suggested rule set:

- choose the strongest positive match from known provider markers
- surface ambiguity as `Unknown` rather than guessing
- never print token fragments, cookie values, or secret lengths

## TDD Plan

1. Add domain tests for `AgentAuthMode` classification.
2. Add application tests for configuration snapshots covering OpenAI OAuth, OpenAI key, OpenRouter key, custom provider, and missing config.
3. Add runtime tests for `hermes-fly list` output to prove the new summary is rendered and redacted.
4. Implement the mapping logic in the application layer and keep CLI formatting in the Commander presenter layer.

## Acceptance Criteria

- `hermes-fly list` reports a stable auth summary for each deployment.
- No raw secrets appear in stdout, logs, snapshots, or test fixtures.
- Existing list behavior remains backward compatible apart from the added summary field.
- Unknown configurations degrade gracefully instead of crashing or mislabeling.

## Risks

- Some legacy deployments may have overlapping config markers.
- Runtime inspection could become slow if the implementation shells out too often per app.
- Secret naming drift across old installs may require compatibility mapping.

## Out of Scope

- Editing provider configuration from the list command
- Displaying reasoning model details beyond auth mode
- Migrating existing deployments to a new auth mechanism
