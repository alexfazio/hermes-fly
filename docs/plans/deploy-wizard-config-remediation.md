# Deploy Wizard Configuration Remediation Plan

> **Source:** Live deploy test of v0.1.8 on 2026-03-07 (session transcript
> preserved at `docs/plans/deploy-test-session-20260307-raw.md`)
>
> **Version target:** v0.1.9

---

## Context

A live deploy of hermes-fly v0.1.8 to Fly.io (app `test-test-99`, region
`ams`, shared-cpu-2x) revealed four configuration bugs that required manual
SSH intervention to get the bot responding. The deploy wizard completed
successfully and the app started, but hermes-agent could not authenticate
with OpenRouter or recognize paired users without manual fixes.

The root cause is a **configuration delivery gap**: the deploy wizard
collects user preferences (API key, model, messaging tokens) and stores
them as Fly.io secrets, but hermes-agent reads configuration from two
files on the persistent volume (`/root/.hermes/.env` and
`/root/.hermes/config.yaml`). Fly secrets are injected as environment
variables in the container, but no code bridges those environment
variables into the files hermes-agent actually reads.

---

## Bug 1: API Key Not Written to `.env`

### Symptom

```text
⚠️ Error code: 401 - {'error': {'message': 'No cookie auth credentials
found', 'code': 401}}
```

### Root Cause

The deploy wizard stores the API key as a Fly secret
(`OPENROUTER_API_KEY`), which becomes a container environment variable.
However, hermes-agent reads `OPENROUTER_API_KEY` from
`/root/.hermes/.env` on the volume — not from the process environment.

**Evidence:**

- `lib/deploy.sh:905` sets the secrets:
  `secrets+=("OPENROUTER_API_KEY=${DEPLOY_API_KEY}" "LLM_MODEL=${DEPLOY_MODEL}")`
- `templates/entrypoint.sh:9-12` copies a **default** `.env` (with empty
  `OPENROUTER_API_KEY=`) from `/opt/hermes/defaults/` on first boot
- No code writes the Fly secret value into the `.env` file

### Manual Workaround (from live test)

```bash
fly ssh console --app <APP> -C "sed -i 's/^OPENROUTER_API_KEY=.*/OPENROUTER_API_KEY=<KEY>/' /root/.hermes/.env"
fly machine restart <MACHINE_ID> --app <APP>
```

### Fix

Add a **secrets-to-env bridge** in `templates/entrypoint.sh` that writes
Fly secret environment variables into `/root/.hermes/.env` after seeding
defaults. This runs on every boot, ensuring secrets always reflect the
latest `fly secrets set` values.

**Affected files:**

- `templates/entrypoint.sh` — add env-var injection after default seeding
- `tests/scaffold.bats` — add tests for env-var bridging behavior

**Env vars to bridge:** `OPENROUTER_API_KEY`, `LLM_MODEL`,
`LLM_BASE_URL`, `LLM_API_KEY`, `NOUS_API_KEY`, `TELEGRAM_BOT_TOKEN`,
`TELEGRAM_ALLOWED_USERS`, `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS`

> **Verified 2026-03-07:** This list matches all 9 Fly secrets set by
> the deploy wizard (lib/deploy.sh:895-922). hermes-agent's .env.example
> contains additional vars (GLM_API_KEY, SLACK_BOT_TOKEN, FAL_KEY, etc.)
> but those are not collected by the deploy wizard and need not be bridged.

---

## Bug 2: OpenRouter Model ID Format Mismatch

### Bug 2 Symptom

```text
⚠️ Error code: 400 - {'error': {'message':
'anthropic/claude-haiku-4-20250506 is not a valid model ID', 'code': 400}}
```

A second attempt with `anthropic/claude-haiku-4-5-20251001` also failed.
The correct OpenRouter ID is `anthropic/claude-haiku-4.5`.

### Bug 2 Root Cause

The model selection table in `lib/deploy.sh:720-724` uses Anthropic API
format model IDs, which OpenRouter does not recognize:

```bash
local model_ids=(
  "anthropic/claude-sonnet-4-20250514"    # wrong
  "anthropic/claude-haiku-4-20250506"     # wrong
  "google/gemini-2.5-flash"
  "meta-llama/llama-4-maverick"
)
```

### Bug 2 Fix

Update model IDs to OpenRouter format. Verified correct IDs:

| Current (Anthropic format)   | Correct (OpenRouter)         |
| ---------------------------- | ---------------------------- |
| `claude-sonnet-4-20250514`   | `anthropic/claude-sonnet-4`  |
| `claude-haiku-4-20250506`    | `anthropic/claude-haiku-4.5` |
| `google/gemini-2.5-flash`    | Same (verified 2026-03-07)   |
| `llama-4-maverick`           | Same (verified 2026-03-07)   |

**Affected files:**

- `lib/deploy.sh:720-724` — update `model_ids` array

**Note:** The Nous and Custom provider paths may have similar issues.
Verify model IDs for all provider paths.

> **Verified 2026-03-07:** Nous path (line 670-681) and Custom path
> (line 683-706) both set model to empty string and have no model_ids
> arrays. Only the OpenRouter path has hardcoded model IDs. No action
> needed for Nous/Custom providers.

---

## Bug 3: `config.yaml` Model Not Updated

### Bug 3 Symptom

After deploy, `config.yaml` still has `default: "anthropic/claude-opus-4.6"`
(the upstream hermes-agent default), not the user's chosen model.

### Bug 3 Root Cause

The wizard stores the model as a Fly secret (`LLM_MODEL`) at
`lib/deploy.sh:905`, but hermes-agent reads the model from
`config.yaml`'s `model.default` field — not from the environment.

The entrypoint copies a default `config.yaml` from
`/opt/hermes/defaults/` on first boot (line 10-11), which contains the
upstream default model (`anthropic/claude-opus-4.6`).

### Bug 3 Manual Workaround (from live test)

```bash
fly ssh console --app <APP> -C "sed -i 's|default: \"anthropic/claude-opus-4.6\"|default: \"anthropic/claude-haiku-4.5\"|' /root/.hermes/config.yaml"
fly machine restart <MACHINE_ID> --app <APP>
```

### Bug 3 Fix

Extend the entrypoint secrets bridge (Bug 1 fix) to also patch
`config.yaml` when `LLM_MODEL` is set in the environment. Use `sed` to
replace the `default:` line under the `model:` section.

**Affected files:**

- `templates/entrypoint.sh` — add `config.yaml` model patching
- `tests/scaffold.bats` — add test for model patching behavior

---

## Bug 4: Pairing Rate Limit Blocks Approved Users

### Bug 4 Symptom

```text
Too many pairing requests right now~ Please try again later!
```

This persists even after the user is in `telegram-approved.json`, and
survives machine restarts. The only workaround was manually clearing the
rate limit file.

### Bug 4 Root Cause

The pairing system writes rate limits to
`/root/.hermes/pairing/_rate_limits.json` on the persistent volume.
When a user sends messages before being paired (or during the pairing
flow), the rate limiter locks them out. After pairing is approved, the
rate limit entry persists and the gateway continues rejecting messages
from the approved user.

**Evidence from live test:**

```json
{
  "telegram:1467489858": 1772896661.1591327,
  "_failures:telegram": 1
}
```

This file existed even though `telegram-approved.json` had the same user
ID approved.

### Bug 4 Manual Workaround (from live test)

```bash
fly ssh console --app <APP> -C "python3 -c \"open('/root/.hermes/pairing/_rate_limits.json','w').write('{}')\""
fly machine restart <MACHINE_ID> --app <APP>
```

### Bug 4 Fix

This is an **upstream hermes-agent bug** (not hermes-fly). The gateway
should clear rate limit entries for a user ID when that user is approved.
However, hermes-fly can mitigate it:

**Option A (hermes-fly mitigation):** After `hermes pairing approve`,
the wizard could clear the rate limit for that user. Not currently
applicable since pairing happens outside the deploy flow.

**Option B (entrypoint mitigation):** On boot, if
`_rate_limits.json` exists and `telegram-approved.json` has entries,
clear rate limit entries for approved user IDs.

**Option C (upstream fix):** File an issue on
`NousResearch/hermes-agent` requesting that the pairing approval
flow clear rate limits for the approved user.

> **Checked 2026-03-07:** No existing upstream issue found for this bug.
> A new issue needs to be filed on NousResearch/hermes-agent.

**Recommended:** Option C (upstream) + Option B (defensive mitigation in
entrypoint).

**Affected files:**

- `templates/entrypoint.sh` — add rate limit cleanup for approved users
- Upstream: `NousResearch/hermes-agent` issue

---

## Implementation Order

| Priority | Bug                    | Effort | Impact         |
| -------- | ---------------------- | ------ | -------------- |
| P0       | Bug 2: Model ID format | Small  | Blocks LLM     |
| P0       | Bug 1: API key → .env  | Medium | Blocks LLM     |
| P1       | Bug 3: config.yaml     | Medium | Wrong model    |
| P2       | Bug 4: Rate limit      | Small  | UX friction    |

**Recommended approach:** Fix Bugs 1-3 together in a single release
(v0.1.9) since they share the entrypoint modification. Bug 4 can be
addressed as a defensive mitigation in the same release or deferred to
an upstream fix.

---

## Verification

1. Fresh deploy with OpenRouter + Haiku: bot responds without manual SSH
2. `fly ssh console -C "grep OPENROUTER_API_KEY /root/.hermes/.env"` shows
   the key from the deploy wizard
3. `fly ssh console -C "grep 'default:' /root/.hermes/config.yaml"` shows
   the selected model in OpenRouter format
4. Pairing flow completes without rate limit blocking
5. `hermes-fly doctor` passes all 7 checks
6. All existing tests pass + new tests for entrypoint bridging

---

## Additional Notes from Live Test

- **SSH setup required:** `fly ssh issue --agent` must run before
  `fly ssh console` works. The `--app` flag is not supported on
  `fly ssh issue` — it operates at the org level.
- **`fly machine restart`** accepts optional machine IDs (`fly machine restart [<id>...]`).
  Without IDs, use `--app <APP>` to target the app. Use `fly machines list`
  to get specific IDs.
- **`hermes logs` is not a valid subcommand** — use `fly logs --app <APP>`
  instead for viewing app logs.

---

## References

- [OpenRouter Claude Sonnet 4 model page](https://openrouter.ai/anthropic/claude-sonnet-4)
- [OpenRouter Claude Haiku 4.5 model page](https://openrouter.ai/anthropic/claude-haiku-4.5)
- [OpenRouter Gemini 2.5 Flash model page](https://openrouter.ai/google/gemini-2.5-flash)
- [OpenRouter Llama 4 Maverick model page](https://openrouter.ai/meta-llama/llama-4-maverick)
- [Fly.io Secrets documentation](https://fly.io/docs/apps/secrets/)
- [fly ssh issue command documentation](https://fly.io/docs/flyctl/ssh-issue/)
- [fly machine restart command documentation](https://fly.io/docs/flyctl/machine-restart/)
- [NousResearch/hermes-agent issues](https://github.com/NousResearch/hermes-agent/issues)
- [hermes-agent messaging user guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/)
