# Hermes-Fly: Hermes Deployment Plan Document

## Overview

Build `hermes-fly`, a Bash CLI tool that automates deploying Hermes Agent to Fly.io with a beginner-friendly, guided experience—from installation to messaging.

## Target Users
Complete beginners with **no prior Fly.io knowledge** - goal: "deploy and forget" with minimal friction
- User runs `hermes-fly deploy` and the follows interactive prompts
 and gets a running Hermes Agent
- Minimal cognitive load for beginners
- Clear documentation
- CLI-embedded help

## Prerequisites

**Supported Platforms:**
- macOS (Intel and Apple Silicon)
- Linux (x86_64 and ARM64)
- **Not supported**: Windows (exit with error, WSL not tested)

**Required Software:**
- `flyctl` >= v0.2.0 (version checked at runtime)
- `git` (for cloning Hermes if needed)
- `curl` (for downloading resources)
- Internet connectivity (checked before deployment)

- 1 month timeline

## Problem Statement

[What problem or need the task addresses - the "why" behind the request]

Users want to run Hermes Agent as a persistent personal AI assistant but but:
- Installing Hermes requires technical knowledge (Python, git, environment setup)
- Running Hermes as a service requires managing servers, Docker, and systemd
- Configuring messaging platforms (Telegram, Discord) requires creating bots and getting tokens
- Maintaining persistent storage across restarts
- Monitoring costs and logs, and troubleshooting issues
- Keeping Hermes updated with the latest features
- Managing API keys securely
- Understanding Fly.io deployment complexity

This creates a high barrier to entry. The target users would benefit from a tool that:
1. **Simplifies** the entire deployment process
2. **Guides** users through each step interactively
3. **Automates** error handling and retries
4. **Provides** clear documentation and troubleshooting help
5. **Reduces** the cognitive load for beginners

6. **Lowers** the barrier to entry for Hermes ownership

7. **Creates** reproducible, reliable deployments

## Solution
[The fully clarified description of what should be built/changed/fixed]

### Core CLI Tool: `hermes-fly`

A **Bash script** (no compilation required) that provides:

**Commands:**
- `hermes-fly deploy` - Interactive deployment wizard (primary command) - includes configuration
- `hermes-fly status` [-a app-name] - Check deployment health, app status, volume info, cost estimate
- `hermes-fly logs` [-a app-name] - View logs (wraps `fly logs` with Hermes-specific formatting)
- `hermes-fly doctor` [-a app-name] - Diagnose common issues (secrets, volume, gateway health)
- `hermes-fly destroy` [-a app-name] - Remove Fly app, volumes, and secrets (confirmation required)

**Out of Scope:**
- `hermes-fly update` - Users run `fly deploy` directly for updates
- Web dashboard, monitoring dashboards
- Configuration migration tooling

**Interactive Prompts:**
- Fly.io authentication (browser-based login if not logged in)
- App name suggestion (auto-generated or custom)
- Region selection (auto-detected based on IP or manual)
- Machine size selection (with cost estimates)
- Persistent storage size (volume sizing)
- LLM provider selection (OpenRouter, Nous Portal, custom)
- API keys (OpenRouter API key, optional others)
- Messaging platforms (Telegram/Discord bot tokens, user IDs)
- Optional features (health endpoint, activity reports)

### Key Features

**1. Deployment Wizard (`hermes-fly deploy`)**
The Interactive TUI with:
- Welcome screen with Hermes overview
- **Platform check**: macOS/Linux only (exit with error on Windows)
- **Prerequisite checks**: flyctl, git, curl availability
- **flyctl version check**: Warn if version is too old (< v0.2.0)
- **Connectivity check**: Verify network access before proceeding
- Fly.io authentication check (retry + re-prompt on failure)
- App name input (auto-generated suggestion like `hermes-USERNAME-123`)
- Region selection (auto-detected, manual override)
- Machine size selection with live cost estimates
  - shared-cpu-1x 256MB: ~$3.50/mo
  - shared-cpu-2x 512MB: ~$7/mo
  - performance-1x 1GB: ~$14/mo
  - dedicated-cpu-1x 1GB: ~$23/mo
- Volume size selection
  - 1GB (light usage)
  - 5GB (recommended)
  - 10GB (heavy usage)
- LLM provider configuration
  - OpenRouter (API key input)
  - Nous Portal (OAuth flow)
  - Custom endpoint (URL + API key)
- Messaging platform setup
  - Telegram: bot token + allowed users
  - Discord: bot token + allowed users
  - Skip messaging for CLI only)
- Optional features
  - Health endpoint toggle
  - Activity reports toggle (daily/weekly)
- Confirmation and deployment
- Progress indicators for each step:
  - Cloning Hermes repository
  - Creating volume
  - Building container
  - Setting secrets
  - Deploying to Fly.io
  - Running health checks
  - Final success message with:
    - App URL
    - Messaging instructions
    - Next steps
    - Cost estimate
    - Quickstart guide link

**2. Configuration Management**
- API keys stored via `fly secrets` (never in code, never in local files)
- Secrets are `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, etc.
- Configuration stored in `~/.hermes/config.yaml` on volume (non-secret settings only)
- **App tracking**: `~/.hermes-fly/config.yaml` stores current app name for multi-instance support
- Automatic backup via Fly volume snapshots (documented)
- Manual backup via `fly vol snapshot` command (documented)

**3. Messaging Setup**
- **Telegram:**
  - Step-by-step bot creation via BotFather
  - User ID retrieval via userinfobot
  - Token configuration via wizard
- **Discord:**
  - Bot creation via Developer Portal
  - Permission setup
  - Token configuration via wizard
- Both platforms documented with:
  - Official Hermes documentation links
  - Troubleshooting tips
  - Security considerations

**4. Deployment Process**
- Check prerequisites (flyctl installed, authenticated, version >= v0.2.0)
- Check platform (exit on Windows)
- Check connectivity (fail fast if offline)
- Generate **minimal Dockerfile** dynamically (wraps Hermes's official install.sh)
- Create Fly volume (1-10GB, configurable)
- Generate fly.toml from template with:
  - Volume mount at `~/.hermes`
  - Health check endpoint
  - Resource limits
  - Auto-stop configuration
- Set secrets via `fly secrets`
- Deploy with `fly deploy` (with progress indicator and timeout)
  - **Default timeout**: 10 min for builds, 5 min for deploys
  - **Override**: `--timeout` flag
  - **Progress**: Show elapsed time and current step
- Run post-deploy health check
- Display final status and instructions

**Dockerfile Generation:**
The Dockerfile is generated at deploy time (not embedded in repo). Structure:
```dockerfile
FROM python:3.11-slim
ARG HERMES_VERSION=main
RUN apt-get update && apt-get install -y git curl
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_VERSION}/scripts/install.sh | bash
WORKDIR /root/.hermes
ENTRYPOINT ["hermes", "gateway"]
```
This approach:
- **Version pinning**: Use `HERMES_VERSION` variable (default: `main`, overridable with `--hermes-version`)
- **Tracks upstream Hermes changes automatically** when using `main`
- **Reproducible deployments** when pinning to specific commit SHA
- **No Dockerfile maintenance burden**
- **Fallback**: Embedded backup Dockerfile if Hermes install.sh is unavailable

**5. Error Handling**
The script provides clear feedback at each step:
- **Always verbose**: Show full command output plus interpretation for all operations
- **Progress indicators**: Show each step (checking prerequisites, creating volume, building, deploying) with ✓/✗ status and elapsed time
- **Actionable hints on failure**:
  - Network timeout → "Retry with --timeout 60"
  - Volume quota exceeded → "Free volume space: fly volumes delete VOL_ID"
  - Auth expired → "Run fly auth login and retry"
  - Region unavailable → "Choose a different region with --region ORD"
- **Automatic retry**: Transient failures (network, API rate limits) retry 3x with exponential backoff and jitter
- **Auto-cleanup on failure**: If deployment fails, partial resources (volumes, apps) are automatically cleaned up
- **Standardized exit codes**: 0=success, 1=general error, 2=auth failure, 3=network error, 4=resource limit

**6. Post-Deploy Output**
After successful deployment, the script exits with:
```
✓ Hermes deployed successfully!

App:          https://hermes-xxx.fly.dev
Status:       running (1 machine)
Volume:       5GB mounted at ~/.hermes
Est. cost:     ~$5.50/month

Next steps:
1. Set up Telegram: @BotFather → /newbot → copy token
2. Run: hermes-fly doctor to verify health
3. View logs: fly logs -a hermes-xxx

Useful commands:
  fly logs -a hermes-xxx       # View logs
  fly ssh console -a hermes-xxx # SSH into machine
  fly status -a hermes-xxx     # Check status
```

```

**7. Diagnostics (`hermes-fly doctor`)**
- Checks:
  - Fly Machine status
  - Volume mount status
  - Hermes process status
  - Gateway health
  - API connectivity
  - Configuration validation
- Clear error messages with actionable fix suggestions
- Links to troubleshooting docs

**8. Destroy (`hermes-fly destroy`)**
- **Confirmation required**: Prompts "Are you sure? This will delete app [NAME], volume [VOL_ID], and all secrets. Type 'yes' to confirm."
- **Safety flag**: `--force` skips confirmation (for automation)
- Removes: Fly app, attached volumes, all secrets
- **Exit code 0** on success, **code 4** if resources not found

### Design Decisions (Clarified)

The following decisions were clarified through specification review:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Rollback** | Auto-cleanup on failure | Prevents partial resource accumulation; simpler for beginners |
| **Auth failure** | Retry + re-prompt with explanation | No failures allowed; guide user through recovery |
| **Timeout handling** | Progress indicator with elapsed time, configurable via `--timeout` | Shows activity; allows override for slow connections |
| **Secret management** | Script prompts with guidance URLs, secrets go to `fly secrets` only | No local secret storage; eliminates exposure risk |
| **Destroy safety** | Confirmation prompt required | Prevents accidental data loss |
| **Error output** | Always verbose (full output + interpretation) | Beginners need full context |
| **Region selection** | Rely on Fly's default, manual override via `--region` | Fly's logic is good; reduces complexity |
| **Documentation** | Both CLI-embedded help and GitHub docs | CLI for quick help, docs for deep dives |
| **Platform support** | macOS/Linux only, exit with error on Windows | WSL adds complexity; focus on common platforms |
| **flyctl version** | Check version, warn if too old | Prevents compatibility issues |
| **Offline mode** | Fail fast with clear error message | Immediate feedback |
| **Self-update** | No update mechanism for hermes-fly | Users re-run installer or manage manually |
| **Exit codes** | Standardized (0=success, 1=general, 2=auth, 3=network, 4=resource) | Enables scripting/automation |
| **Cost estimation** | Fetch live pricing from Fly.io API (fallback to hardcoded) | Accurate, always current |
| **Uninstall** | Manual only, document steps | Simple, no additional complexity |
| **Multi-instance** | Support multiple apps, track in config file | Users may want personal/work separation |
| **Script logs** | Log to `~/.hermes-fly/hermes-fly.log` | Enables debugging |
| **App tracking** | Config file default with `-a` flag override | Remembers last deployed app |
| **Hermes version** | Pin to specific commit SHA via `HERMES_VERSION` variable | Reproducible deployments |
| **Upstream fallback** | Embedded Dockerfile if Hermes install.sh unavailable | Resilience to upstream changes |
| **Install security** | SHA256 checksum verification | Verify integrity before execution |
| **Testing** | shellcheck + bats-core + manual E2E | Quality assurance |

**App Configuration File** (`~/.hermes-fly/config.yaml`):
```yaml
current_app: hermes-johndoe-123
apps:
  - name: hermes-johndoe-123
    region: ord
    deployed_at: 2024-01-15T10:30:00Z
```

**Exit Codes:**
- `0` - Success
- `1` - General error
- `2` - Authentication failure
- `3` - Network/connectivity error
- `4` - Resource limit exceeded (quota, volume space)

### Technical Architecture

```
hermes-fly/
├── hermes-fly              # Main bash script (entry point)
├── lib/
│   ├── deploy.sh           # Deploy wizard logic
│   ├── status.sh           # Status command
│   ├── logs.sh             # Logs command
│   ├── doctor.sh           # Diagnostics
│   ├── destroy.sh          # Cleanup logic
│   ├── fly-helpers.sh      # Fly.io API wrappers
│   ├── docker-helpers.sh   # Dockerfile generation
│   ├── messaging.sh        # Telegram/Discord setup
│   └── ui.sh               # Shared UI (prompts, spinners, colors)
├── templates/
│   ├── Dockerfile.template # Dockerfile generator
│   └── fly.toml.template   # Fly config template
├── scripts/
│   └── install.sh          # curl | bash installer
├── docs/
│   ├── getting-started.md
│   ├── messaging.md
│   └── troubleshooting.md
├── README.md
└── LICENSE
```

**Key Design Decisions:**
- **Bash script** (not Go): No compilation, readable by beginners, easy to debug
- **Source-able libraries**: Each command in lib/ for modularity
- **CLI-embedded help**: `hermes-fly help deploy` shows full guide inline
- **Generated artifacts**: Dockerfile and fly.toml generated at deploy time
- **Logging**: All operations logged to `~/.hermes-fly/hermes-fly.log`

### Data Flow
```
┌── User runs:
│   curl -fsSL get.hermes-fly.dev | bash
│       ↓
├── User runs: hermes-fly deploy
│       ↓
├── Script checks prerequisites (flyctl, auth)
│       ↓
├── Interactive prompts for config
│       ↓
├── Generates Dockerfile (wraps Hermes install.sh)
│       ↓
├── Generates fly.toml from template
│       ↓
├── Creates Fly Volume (1-10GB)
│       ↓
├── Sets secrets via fly secrets
│       ↓
├── Runs fly deploy
│       ↓
└── Outputs success message with URLs + commands
        └── User accesses Hermes via Telegram/Discord

Ongoing management: User uses flyctl directly (fly logs, fly deploy, fly ssh)
```

### Installation Security

**Recommended Install Method:**
```bash
# Download and verify
curl -fsSL https://get.hermes-fly.dev/install.sh -o install.sh
curl -fsSL https://get.hermes-fly.dev/install.sh.sha256 -o install.sh.sha256

# Verify checksum
sha256sum -c install.sh.sha256

# Review before running
less install.sh

# Execute
bash install.sh
```

**Quick Install (with automatic verification):**
```bash
curl -fsSL https://get.hermes-fly.dev/install.sh | bash
```

The install script includes built-in SHA256 verification against a known-good checksum embedded in the script itself.

### Success Criteria
After deployment:
- [ ] Messaging works: User can send a Telegram/Discord message and get a response
- [ ] CLI works: Running `hermes` from within the Fly Machine works
- [ ] Persistence works: Files in `~/.hermes` persist across `hermes` restart
- [ ] Health checks pass: app is healthy
- [ ] `hermes-fly doctor` command passes all checks
- [ ] Estimated monthly cost displayed (wizard)
- [ ] Post-deploy checklist is shown

## Persistence Strategy
**Fly Volume (Primary approach)**
- Mounts at `~/.hermes` directory
- Survives Machine restarts, deployments, and scales with the Machine
- Snapshots provide backup capability (`fly vol snapshot`)
- **Configuration:** 1-10GB, configurable during wizard
- **Implementation:** Simple, reliable, automatic backups
- **Trade-offs:**
  - Tied to single Machine (can't scale horizontally)
  - Requires volume management (create, extend, snapshot)
  - **Alternative: Tigris object storage (documented)**
  - For users who need stateless, scalable deployment
  - More complex setup (requires Tigris credentials)
  - Sync on startup/shutdown
  - **Recommendation:** Fly Volume for beginners because:
    - Simpler mental model
    - No additional infrastructure
    - Automatic persistence
    - **Documented** as alternative in `docs/configuration.md`

## Security Considerations

**Important:** Security is primarily Hermes's responsibility. This tool automates deployment but does not modify Hermes's security model.

1. **API keys** stored via `fly secrets` (Fly.io's encrypted secret storage)
2. **User allowlists** enforced by Hermes (TELEGRAM_ALLOWED_USERS, DISCORD_ALLOWED_USERS)
3. **Trust boundary**: Hermes process has access to all secrets set for the Fly app - this is Hermes's design choice
4. **Container isolation**: Hermes runs in Fly Machine with standard container isolation
5. **Network**: Fly.io provides private networking; Hermes gateway is the only exposed service
6. **Updates**: Security patches come from Hermes updates - user runs `fly deploy` to update

For Hermes security details, see: https://github.com/NousResearch/hermes-agent#security

## Cost estimation

**Live Pricing (Primary):**
The script fetches current pricing from Fly.io's pricing API when available.

**Fallback Estimates (when API unavailable):**
| Machine size | vCPU | RAM | Est. Monthly Cost |
|------------|------|-----|----------------|
| shared-cpu-1x 256MB | 1 | ~$3.50 |
| shared-cpu-2x 512MB | 2 | ~$7 |
| shared-cpu-2x 1GB | 1 | ~$14 |
| dedicated-cpu-1x 1GB | 1 | ~$23 |

Additional costs:
- Volume storage: $0.15/GB/month
- Bandwidth: $0.02/GB (free tier: 1GB/month)
- Messaging API calls: varies by usage

## Testing Strategy

### Automated Testing
- **shellcheck**: Static analysis for all bash scripts (CI-enforced)
- **bats-core**: Unit tests for library modules (lib/*.sh)
- **Test coverage**: Core functions in lib/ should have >80% coverage

### Manual Testing Checklist
1. **Fresh deployment**
   - [ ] Install via curl | bash
   - [ ] Complete deployment wizard
   - [ ] Verify messaging works (send test message)
   - [ ] Verify CLI works (SSH into machine)
   - [ ] Check persistence (restart machine, verify files intact)
   - [ ] Run `hermes-fly doctor`
   - [ ] Test logs command

   - [ ] Test status command

2. **Error scenarios**
   - [ ] Test with invalid API keys
   - [ ] Test with missing flyctl
   - [ ] Test with network issues
   - [ ] Test with volume full scenario
   - [ ] Test with region unavailability

3. **Messaging platforms**
   - [ ] Telegram bot setup
   - [ ] Discord bot setup
   - [ ] Test message delivery
   - [ ] Test user allowlist

## Documentation Plan

**CLI-Embedded Help (Primary):**
- `hermes-fly --help` - Overview and command list
- `hermes-fly deploy --help` - Detailed deploy guide with examples
- `hermes-fly doctor --help` - Diagnostics guide
- All help text embedded in script for offline access

**GitHub Docs (Detailed Guides):**
1. **README.md** - Quick start, features, installation, security notice
2. **docs/getting-started.md** - Detailed walkthrough with screenshots
3. **docs/architecture.md** - System design, data flow
4. **docs/configuration.md** - All configuration options
5. **docs/messaging.md** - Telegram/Discord setup guides with URLs
6. **docs/troubleshooting.md** - Common issues and solutions
7. **docs/experimental.md** - Health endpoint, activity reports, Tigris
8. **docs/uninstall.md** - Manual removal steps

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Project structure setup (bash script + lib/ modules)
- [ ] Argument parsing with subcommand dispatch
- [ ] UI helpers (prompts, spinners, colors, progress indicators)
- [ ] Fly.io API wrappers (fly apps, fly volumes, fly secrets)
- [ ] Template system (Dockerfile, fly.toml)

### Phase 2: Core Commands (Week 2)
- [ ] Deploy command with interactive wizard
- [ ] Dockerfile generator (wraps Hermes install.sh)
- [ ] Status command
- [ ] Logs command

### Phase 3: Polish (Week 3)
- [ ] Doctor command (diagnostics)
- [ ] Destroy command (cleanup)
- [ ] Error handling with actionable hints
- [ ] README documentation
- [ ] CLI-embedded help

### Phase 4: Testing & Release (Week 4)
- [ ] Manual testing (fresh Fly account, deploy, verify)
- [ ] Bug fixes
- [ ] Install script (curl | bash)
- [ ] GitHub release

## Open Questions
- [ ] Does Fly.io have a pricing API for live cost estimation?
  - **Status**: Needs verification. If no API exists, fallback to hardcoded estimates with manual update process.
  - **Finding** [HIGH]: Fly.io does not expose a public pricing API. Official docs refer to fly.io/pricing for costs and `fly platform vm-sizes` CLI for machine types (not pricing). Cost examples use hardcoded estimates. ([Fly.io Cost Management](https://fly.io/docs/about/cost-management/)). **Recommendation**: Use hardcoded pricing with versioned config file; implement `fly platform vm-sizes --json` for dynamic machine types; add `--update-pricing` flag to scrape pricing page as fallback.
- [ ] Should we build a web dashboard for monitoring? (post-MVP consideration)
  - **Finding** [HIGH]: Industry best practices favor existing observability tools (Grafana, Datadog, Azure Monitor) over custom dashboards. Key AI agent metrics include: response latency, task success rate, token consumption, error rates, and user satisfaction. Building custom dashboards requires $10K-$50K+ investment. ([Azure AI Agent Monitoring](https://learn.microsoft.com/en-us/training/modules/manage-optimize-agent-investment-azure/1-monitor-optimize-agent-use/)). **Recommendation**: Document as stretch goal; recommend Grafana/Prometheus integration via Fly.io metrics export for production-ready monitoring with minimal dev cost.
- [ ] Should we support WhatsApp/Slack? (document as stretch goal)
  - **Finding** [HIGH]: WhatsApp Business API requires Meta Business verification (24-72 hours), BSP fees ($50-$500+/month), and per-message pricing ($0.02-$0.10/message). Slack requires OAuth 2.0, workspace membership, and $8.75-$18/user/month pricing. Both have significantly higher barriers than Telegram (free) and Discord (free bot tier). ([WhatsApp Pricing](https://developers.facebook.com/docs/whatsapp/pricing)). **Recommendation**: Document as stretch goal with caveats; WhatsApp requires business verification, Slack requires workspace membership - both unsuitable for personal AI assistant beginner use case.
- [ ] Should we add GitHub Actions for automated deployment? (document as alternative)
  - **Finding** [HIGH]: GitHub Actions offers free CI/CD for public repos with native Fly.io integration via FLY_API_TOKEN secret. Common patterns: auto-deploy on push to main, matrix testing, cache optimization, health monitoring. Requires repo setup, secret management, CI/CD knowledge - adds complexity for beginners. ([Fly.io GitHub Actions Guide](https://fly.io/docs/app-guides/continuous-deployment-with-github-actions/)). **Recommendation**: Document as alternative for advanced users; create .github/workflows/deploy.yml template in docs/. Keep hermes-fly deploy as primary (simpler) method for beginners.
- [ ] What metrics should we collect for activity reports?
  - **Finding** [HIGH]: Standard AI agent metrics: Performance (response latency, task success rate, throughput), Quality (user satisfaction, error rates), Cost (token consumption, cost per task), Business (task achievement rate). For activity reports, most actionable: message count by platform, average response time, task success rate, token usage/estimated cost, active days. ([Azure AI Monitoring](https://learn.microsoft.com/en-us/training/modules/manage-optimize-agent-investment-azure/1-monitor-optimize-agent-use/)). **Recommendation**: Collect message count, response latency, task success rate, token usage/cost, active days. Weekly digest format recommended for personal AI assistants.
- [ ] How should we handle multi-region deployments?
  - **Finding** [HIGH]: Fly.io supports multi-region via fly scale count with multiple regions, anycast IP routing, automatic failover. However, Fly volumes do NOT replicate across regions - requires LiteFS, external DBs, or custom sync. Adds operational complexity and cross-region traffic costs without clear benefit for single-user personal AI assistant. ([Fly.io Regions](https://fly.io/docs/reference/regions/)). **Recommendation**: Document as advanced/enterprise consideration, not MVP. Single-region with automated backups is simpler for target users. If needed, use external DB for state, single region for compute.
- [ ] Should we build a Terraform provider for infrastructure management?
  - **Finding** [HIGH]: No official Terraform provider for Fly.io exists. Using Terraform would require local-exec provisioners with flyctl - non-standard pattern that defeats Terraform's state management benefits. Fly.io's native tools (flyctl, fly.toml) are already optimized for infrastructure management. ([HashiCorp Terraform Registry](https://registry.terraform.io/)). **Recommendation**: Do NOT build Terraform provider. Fly.io native tooling provides excellent infrastructure management. Terraform is suited for traditional cloud (AWS/Azure/GCP); Fly.io edge-compute model is not a good fit.

- [ ] Should we add a configuration migration tool for Hermes updates?
  - **Finding** [MEDIUM]: Config migration is a known pain point - Oh My OpenCode had issues where migration deleted agent overrides. Best practices: backup before migration, automated tools, detailed changelogs, 'additive-only' config design, clear guides. Building robust tool requires understanding Hermes config format evolution. ([Oh My OpenCode Issue #775](https://github.com/code-yeongyu/oh-my-opencode/issues/775)). **Recommendation**: Implement backup-before-update in hermes-fly update (copy ~/.hermes with timestamp). Coordinate with Hermes maintainers on config versioning. Start conservative: backup, update, validate. Add format migration only for breaking config changes.
- [ ] How should we handle Hermes major version changes (breaking changes)?
  - **Finding** [MEDIUM]: API versioning best practices: detailed changelogs, deprecated interface docs, migration guides, semantic versioning. hermes-fly should act as compatibility layer - checking version and warning before breaking updates. ([API Version Control](https://m.blog.csdn.net/gitblog_00041/article/details/155254337)). **Recommendation**: Implement version-aware updates: (1) Check release notes for breaking changes, (2) Warn/confirm for major version jumps, (3) Auto-backup before major updates, (4) Document rollback (fly deploy --rollback), (5) Post-update validation via hermes-fly doctor. Consider pinning to minor version ranges by default.
- [ ] Should we build a library for programmatic Hermes access?
  - **Finding** [HIGH]: Modern AI agent libraries (Agentic, OpenAI Agents SDK) use standardized tool interfaces with multi-SDK compatibility. Requires: unified interface, type safety, error handling, security guardrails, monitoring. Agentic demonstrates cross-platform patterns from single codebase. ([Agentic Library](https://github.com/lgrammel/agentic)). **Recommendation**: Do NOT build programmatic library for MVP. Hermes is CLI-first with potentially unstable internal APIs. If needed later: (1) Document internal APIs as experimental, (2) Create thin CLI wrapper with structured output, (3) Coordinate with Hermes maintainers on official API exposure.
- [ ] Should we support multiple Hermes instances per worktrees?
  - **Finding** [HIGH]: Git worktrees enable multiple independent working directories on different branches. Claude Code has native worktree support for parallel AI agent development. However, multiple Hermes instances require: separate Fly apps, volumes, secrets, multiplied costs. Pattern suited for dev workflows, not production personal assistant use. ([Claude Code Worktrees](https://docs.anthropic.com/en/docs/claude-code/worktrees)). **Recommendation**: Do NOT support for MVP. Feature targets advanced dev workflows, not beginner deployment. Document as advanced pattern. Each instance requires separate Fly app/volume/costs - too complex for target users.

## Verification
[How to verify the solution works - concrete steps to test the result/outcome/effects of the completed task]

1. **End-to-end deployment test:**
   - Fresh Fly.io account
   - Run `hermes-fly deploy` with Telegram configuration
   - Send test message via Telegram
   - Verify response received
   - Run `hermes-fly doctor` and confirm all checks pass

2. **Persistence verification:**
   - Deploy Hermes with volume
   - Create a memory entry via Hermes
   - Restart the Fly Machine
   - Verify memory entry persists
   - Run `hermes-fly status` to confirm volume health

3. **Destruction test:**
   - Run `hermes-fly destroy`
   - Verify app, volumes, and secrets are removed

4. **User acceptance test:**
   - Have 3-5 beginners attempt deployment
   - Collect feedback on:
     - Confusion points
     - Error messages
     - Documentation gaps
     - Feature requests
   - Iterate based on feedback

## Conclusion

This plan provides a comprehensive roadmap for building `hermes-fly`, a tool that makes deploying Hermes Agent on Fly.io accessible to complete beginners. The MVP focuses on:

1. **Simplicity** - Bash script, guided wizard, minimal configuration
2. **Reliability** - Auto-retry, health checks, volume persistence
3. **Usability** - Clear documentation, actionable error hints, troubleshooting tools
4. **Maintainability** - Modular bash libraries, generated Dockerfile, CLI-embedded help

The tool addresses the core problem (complexity) by providing a streamlined, guided experience that handles the technical details automatically, allowing beginners to focus on using Hermes rather than managing infrastructure.

**Out of Scope (Post-MVP):**
- Update mechanism (users run `fly deploy` directly)
- Web dashboard (use Fly.io native tools or Grafana)
- WhatsApp/Slack support (Telegram/Discord only)
- Configuration migration (document manual process)

---

## References

- [Fly.io Cost Management Documentation](https://fly.io/docs/about/cost-management/)
- [Fly.io Pricing Page](https://fly.io/pricing)
- [Azure AI Agent Monitoring](https://learn.microsoft.com/en-us/training/modules/manage-optimize-agent-investment-azure/1-monitor-optimize-agent-use/)
- [WhatsApp Business API Pricing](https://developers.facebook.com/docs/whatsapp/pricing)
- [Fly.io GitHub Actions Guide](https://fly.io/docs/app-guides/continuous-deployment-with-github-actions/)
- [Fly.io Regions Documentation](https://fly.io/docs/reference/regions/)
- [HashiCorp Terraform Registry](https://registry.terraform.io/)
- [Oh My OpenCode Config Migration Issue](https://github.com/code-yeongyu/oh-my-opencode/issues/775)
- [Agentic Cross-SDK AI Agent Library](https://github.com/lgrammel/agentic)
- [Claude Code Worktrees Documentation](https://docs.anthropic.com/en/docs/claude-code/worktrees)
