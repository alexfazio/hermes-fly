const HELP_TEXT = `hermes-fly — Deploy Hermes Agent to Fly.io

Usage:
  hermes-fly <command> [options]

Commands:
  deploy              Interactive deployment wizard
  update [-a APP]     Update existing deployment to latest version
  resume [-a APP]     Resume checks after interrupted deploy
  list                List all deployed agents
  status [-a APP]     Check deployment health
  logs [-a APP]       View application logs
  doctor [-a APP]     Diagnose common issues
  console             Open Hermes CLI or a shell inside a deployed agent
  exec [-a APP]       Execute a raw command in the deployed machine
  agent [-a APP]      Run a Hermes CLI subcommand in the deployed machine
  destroy [APP...]    Remove one or more deployments
  help                Show this help message
  version             Show version

Options:
  -a APP              Specify app name (defaults to current app)
  -s APP              Open a shell for the specified app (console only)
  --force             Skip confirmation prompts (destroy only)
  --help, -h          Show help
  --version, -v       Show version

Examples:
  hermes-fly deploy                  # Start deployment wizard
  hermes-fly update                  # Update current app to latest
  hermes-fly update -a my-hermes     # Update specific app
  hermes-fly resume                  # Resume checks for current app
  hermes-fly status                  # Check current app status
  hermes-fly status -a my-hermes     # Check specific app
  hermes-fly console -a my-hermes    # Open Hermes CLI in the deployed agent
  hermes-fly console -s my-hermes    # Open a shell in the deployed agent
  hermes-fly exec -a my-hermes -- ls -la
  hermes-fly agent -a my-hermes model
  hermes-fly doctor                  # Run diagnostics
  hermes-fly destroy --force         # Force destroy current app without confirmation
  hermes-fly destroy app1 app2       # Destroy multiple apps in one command

Documentation:
  https://github.com/alexfazio/hermes-fly
`;

export function runHelpCommand(stdout: { write: (s: string) => void } = process.stdout): void {
  stdout.write(HELP_TEXT);
}
