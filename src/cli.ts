import { Command } from "commander";
import { runListCommand } from "./commands/list.js";
import { runStatusCommand } from "./commands/status.js";
import { runLogsCommand } from "./commands/logs.js";
import { HERMES_FLY_TS_VERSION } from "./version.js";

export function buildProgram(): Command {
  const versionLine = `hermes-fly ${HERMES_FLY_TS_VERSION}`;
  const program = new Command()
    .name("hermes-fly")
    .description("Hermes Fly TypeScript CLI scaffold")
    .version(versionLine, "--version", "Show version");

  program
    .command("version")
    .description("Show version")
    .helpOption(false)
    .allowUnknownOption(true)
    .allowExcessArguments(true)
    .action(() => {
      process.stdout.write(`${versionLine}\n`);
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

  return program;
}

export async function run(argv: string[]): Promise<void> {
  const program = buildProgram();
  await program.parseAsync(argv);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run(process.argv).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`TS CLI error: ${message}\n`);
    process.exitCode = 1;
  });
}
