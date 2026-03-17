const HELP_TEXT = `hermes-fly — Deploy Hermes Agent to Fly.io

Usage:
  hermes-fly <command> [options]

Commands:
  deploy              Interactive deployment wizard
  resume [-a APP]     Resume checks after interrupted deploy
  list                List all deployed agents
  status [-a APP]     Check deployment health
  logs [-a APP]       View application logs
  doctor [-a APP]     Diagnose common issues
  console [-a APP]    Open Hermes CLI inside a deployed agent
  destroy [APP...]    Remove one or more deployments
  help                Show this help message
  version             Show version

Options:
  -a APP              Specify app name (defaults to current app)
  --force             Skip confirmation prompts (destroy only)
  --help, -h          Show help
  --version, -v       Show version

Examples:
  hermes-fly deploy                  # Start deployment wizard
  hermes-fly resume                  # Resume checks for current app
  hermes-fly status                  # Check current app status
  hermes-fly status -a my-hermes     # Check specific app
  hermes-fly console -a my-hermes    # Open Hermes CLI in the deployed agent
  hermes-fly doctor                  # Run diagnostics
  hermes-fly destroy --force         # Force destroy current app without confirmation
  hermes-fly destroy app1 app2       # Destroy multiple apps in one command

Documentation:
  https://github.com/alexfazio/hermes-fly
`;

export function runHelpCommand(stdout: { write: (s: string) => void } = process.stdout): void {
  stdout.write(HELP_TEXT);
}
