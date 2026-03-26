# Hermes Fly

![Hermes Fly cover](docs/assets/hermes-fly-cover.png?v=20260308)

Deploy [Hermes Agent](https://github.com/NousResearch/hermes-agent) to
[Fly.io](https://fly.io) with a single command.

Interactive CLI wizard that provisions, configures,
and manages a Hermes instance on Fly.io.

## Features

- **Deploy wizard** -- guided setup that provisions your app, volume, VM, and secrets
- **Update** -- update existing deployments to latest Hermes version without data loss
- **Status** -- check app health, machine state, region, and URL at a glance
- **Logs** -- stream or tail live application logs
- **Doctor** -- run diagnostic checks to verify connectivity, auth, and app health
- **Destroy** -- clean teardown of app, volumes, and local config
- **Messaging** -- optional Telegram and Discord notification setup

## Quick Start

### Install

```bash
curl -fsSL "https://raw.githubusercontent.com/alexfazio/hermes-fly/main/scripts/install.sh" | bash
```

This installs the latest published `hermes-fly` release by default. The
installer prefers packaged release assets and falls back to a source build only
when an older tag does not provide one. Fresh installs default to a user-local
launcher in `~/.local/bin` plus an OS-specific install home (`~/.local/share`
on Linux via XDG defaults, `~/Library/Application Support` on macOS). Existing
installs are upgraded in place so current `/usr/local` users do not get moved
silently. To pin a specific release:

```bash
HERMES_FLY_VERSION=vX.Y.Z curl -fsSL "https://raw.githubusercontent.com/alexfazio/hermes-fly/main/scripts/install.sh" | bash
```

Install channels are also supported via `HERMES_FLY_CHANNEL`:

- `stable` (default): latest release tag
- `preview`: currently follows `stable` until a dedicated preview stream is published
- `edge`: installs from moving `main` (non-reproducible)

```bash
HERMES_FLY_CHANNEL=edge curl -fsSL "https://raw.githubusercontent.com/alexfazio/hermes-fly/main/scripts/install.sh" | bash
```

Or clone and run directly:

```bash
git clone https://github.com/alexfazio/hermes-fly.git
cd hermes-fly
./hermes-fly deploy
```

### Deploy

```bash
hermes-fly deploy
```

The wizard walks you through:

1. Platform and prerequisite checks
2. Fly.io authentication
3. App name, region, VM size, and volume configuration
4. API key and model selection
5. Optional messaging setup (Telegram / Discord)
6. Build, deploy, and health verification

## Commands

| Command              | Description                                       |
| -------------------- | ------------------------------------------------- |
| `hermes-fly deploy`  | Launch the interactive deploy wizard              |
| `hermes-fly update`  | Update existing deployment to latest version      |
| `hermes-fly status`  | Show app status, machine state, and URL           |
| `hermes-fly logs`    | Stream live application logs                      |
| `hermes-fly doctor`  | Run diagnostic checks on deployment               |
| `hermes-fly destroy` | Tear down app, volumes, and local config          |

## Cost Estimates

Fly.io charges are usage-based. Typical monthly costs:

| VM Size        | Mem    | VM      | +1 GB  | +5 GB  | +10 GB |
| -------------- | ------ | ------- | ------ | ------ | ------ |
| shared-cpu-1x  | 256 MB | ~$2.02  | $2.17  | $2.77  | $3.52  |
| shared-cpu-2x  | 512 MB | ~$4.04  | $4.19  | $4.79  | $5.54  |
| performance-1x | 2 GB   | ~$32.19 | $32.34 | $32.94 | $33.69 |

Volume storage: $0.15/GB/month. See [Fly.io Pricing](https://fly.io/pricing)
and [Fly.io Calculator](https://fly.io/calculator) for current rates.

## Prerequisites

- **flyctl** -- the
  [Fly.io CLI](https://fly.io/docs/flyctl/install/).
- **macOS or Linux** -- Windows is not supported.
- **A Fly.io account** -- sign up free at [fly.io](https://fly.io).
- **curl** and **git** -- standard on most systems.

If `hermes-fly` is not already on your `PATH`, the installer prints the exact
`export PATH=...` command to add the launcher directory for your shell.

## Security

Secrets (API keys, bot tokens) are stored via
`fly secrets set` and never written to disk. They
are injected as environment variables at runtime.
No secrets appear in fly.toml, Dockerfile, or
local config.

## Testing & Robustness

The prerequisite auto-install feature is tested across diverse environments:

- **57 edge case tests** covering platform detection, PATH safety, and signal handling
- **370+ total tests** with zero regressions and 100% pass rate
- **Explicit edge case validation** for:
  - Platform detection (unsupported platforms, fallback behavior)
  - PATH modifications in restricted environments
  - Signal handling (SIGTERM, SIGINT, SIGKILL cleanup)
  - Binary & malformed output handling
  - CI/CD integration (--no-auto-install flag, CI=true bypass)
  - Security hardening (command injection prevention)
  - Boundary conditions (long paths, special characters, empty inputs)
  - Permission errors (sudo failures, write denied)

**See [docs/EDGE_CASE_HANDLING.md](docs/EDGE_CASE_HANDLING.md)** for details
on edge case handling and test coverage.

## Runtime

`hermes-fly` dispatches all commands through Commander.js (TypeScript runtime via `node dist/cli.js`).
No migration environment flags are required.

### Architecture Boundary Check

Run this check to enforce DDD layer boundaries in `src/contexts` during migration.

```bash
npm run arch:ddd-boundaries
```

### Domain Primitive Tests

```bash
npm run test:domain-primitives
```

These tests validate domain invariants with zero IO mocks.

### Parity Harness

```bash
npm run parity:check
```

Captures deterministic command snapshots and compares them to the committed parity baseline.


## License

[MIT](LICENSE)

## Documentation

See the [docs/](docs/) directory for detailed guides:

- [Getting Started](docs/getting-started.md) -- step-by-step deployment walkthrough
- [Messaging Setup](docs/messaging.md) -- Telegram and Discord configuration
- [Troubleshooting](docs/troubleshooting.md) -- common issues and fixes
- [Release Operations](docs/release-operations.md) -- stable promotion gates, drift checks, and rollback playbook

---

## References

- [Fly.io Detailed Pricing Documentation](https://fly.io/docs/about/pricing/)
- [Fly.io Pricing Overview](https://fly.io/pricing)
- [Fly.io flyctl Installation Guide](https://fly.io/docs/flyctl/install/)
- [NousResearch hermes-agent Repository](https://github.com/NousResearch/hermes-agent)
- [alexfazio hermes-fly Repository](https://github.com/alexfazio/hermes-fly)
