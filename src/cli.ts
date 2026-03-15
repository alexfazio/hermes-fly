import { Command } from "commander";
import { runListCommand } from "./commands/list.js";
import { runStatusCommand } from "./commands/status.js";
import { runLogsCommand } from "./commands/logs.js";
import { runHelpCommand } from "./commands/help.js";
import { runVersionCommand } from "./commands/version.js";
import { runDeployCommand } from "./commands/deploy.js";
import { runResumeCommand } from "./commands/resume.js";
import { runDoctorCommand } from "./commands/doctor.js";
import { runDestroyCommand } from "./commands/destroy.js";
import { HERMES_FLY_TS_VERSION } from "./version.js";

export function buildProgram(): Command {
  const versionLine = `hermes-fly ${HERMES_FLY_TS_VERSION}`;
  const program = new Command()
    .name("hermes-fly")
    .description("Hermes Fly CLI")
    .version(versionLine, "--version", "Show version")
    .helpOption("-h, --help", "Show help");

  // Disable Commander's built-in help command so we can register our own
  program.helpCommand(false);

  program
    .command("deploy")
    .description("Deployment Wizard — deploys Hermes Agent to Fly.io")
    .option("--channel <channel>", "Deploy channel: stable, preview, or edge", "stable")
    .option("--no-auto-install", "Skip automatic installation of missing prerequisites")
    .action(async (opts) => {
      const args: string[] = [];
      if (opts.channel && opts.channel !== "stable") args.push("--channel", opts.channel);
      if (!opts.autoInstall) args.push("--no-auto-install");
      process.exitCode = await runDeployCommand(args);
    });

  program
    .command("resume")
    .description("Resume checks after interrupted deploy")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async (_, cmd: Command) => {
      process.exitCode = await runResumeCommand(cmd.args);
    });

  program
    .command("list")
    .description("List deployed agents")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async () => {
      process.exitCode = await runListCommand();
    });

  program
    .command("status")
    .description("Show status of a deployed agent")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async (_, cmd: Command) => {
      process.exitCode = await runStatusCommand(cmd.args);
    });

  program
    .command("logs")
    .description("Show logs for a deployed agent")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async (_, cmd: Command) => {
      process.exitCode = await runLogsCommand(cmd.args);
    });

  program
    .command("doctor")
    .description("Diagnose common issues")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async (_, cmd: Command) => {
      process.exitCode = await runDoctorCommand(cmd.args);
    });

  program
    .command("destroy")
    .description("Remove deployment")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(async (_, cmd: Command) => {
      process.exitCode = await runDestroyCommand(cmd.args);
    });

  program
    .command("help")
    .description("Show help message")
    .helpOption(false)
    .action(() => {
      runHelpCommand();
    });

  program
    .command("version")
    .description("Show version")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(() => {
      runVersionCommand();
    });

  return program;
}

export async function run(argv: string[]): Promise<void> {
  const program = buildProgram();

  // Override Commander's unknown command error to match expected format
  program.on("command:*", (operands: string[]) => {
    process.stderr.write(`[error] Unknown command: ${operands[0]}\n`);
    process.exitCode = 1;
  });

  // Show help (exit 0) when no arguments given
  if (argv.length <= 2) {
    runHelpCommand();
    return;
  }

  await program.parseAsync(argv);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run(process.argv).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`TS CLI error: ${message}\n`);
    process.exitCode = 1;
  });
}
