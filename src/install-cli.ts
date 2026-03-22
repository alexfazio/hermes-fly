import { Command } from "commander";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { NodeInstallerPlatform } from "./contexts/installer/infrastructure/adapters/node-installer-platform.js";
import { InstallerPlan, type InstallChannel, type InstallMethod } from "./contexts/installer/domain/install-plan.js";
import { resolveInstallerPaths } from "./contexts/installer/domain/installer-path-policy.js";
import { runInstallSession } from "./contexts/installer/application/use-cases/run-install-session.js";
import type { InstallerBootstrapPort } from "./contexts/installer/application/ports/installer-shell.port.js";

export interface InstallCommandInput {
  platform?: string;
  arch?: string;
  installChannel?: InstallChannel;
  installMethod?: InstallMethod;
  installRef?: string;
  installHome?: string;
  binDir?: string;
  sourceDir?: string;
  version?: string;
}

export type InstallCommandHandler = (input: InstallCommandInput) => Promise<number>;

function detectPlatform(): string {
  switch (process.platform) {
    case "darwin":
      return "darwin";
    case "linux":
      return "linux";
    default:
      throw new Error(`Unsupported platform: ${process.platform}`);
  }
}

function detectArch(): string {
  switch (process.arch) {
    case "x64":
      return "amd64";
    case "arm64":
      return "arm64";
    default:
      throw new Error(`Unsupported architecture: ${process.arch}`);
  }
}

function resolveInstallChannel(channel?: string, env: NodeJS.ProcessEnv = process.env): InstallChannel {
  const resolved = channel?.trim() || env.HERMES_FLY_CHANNEL?.trim() || "latest";
  switch (resolved) {
    case "latest":
    case "stable":
    case "preview":
    case "edge":
      return resolved;
    default:
      return "latest";
  }
}

function resolveCommandHomeDir(contextHomeDir: string | undefined, env: NodeJS.ProcessEnv = process.env): string {
  const explicitHomeDir = contextHomeDir?.trim();
  if (explicitHomeDir) {
    return explicitHomeDir;
  }

  const envHomeDir = env.HOME?.trim();
  if (envHomeDir) {
    return envHomeDir;
  }

  return homedir();
}

export interface InstallCommandContext {
  env?: NodeJS.ProcessEnv;
  homeDir?: string;
  userId?: number;
}

export async function runInstallCommand(
  input: InstallCommandInput,
  shell: InstallerBootstrapPort = new NodeInstallerPlatform(),
  sessionRunner: typeof runInstallSession = runInstallSession,
  context: InstallCommandContext = {},
): Promise<number> {
  const env = context.env ?? process.env;
  const homeDir = resolveCommandHomeDir(context.homeDir, env);
  const userId = context.userId ?? (typeof process.getuid === "function" ? process.getuid() : undefined);
  const platform = input.platform ?? detectPlatform();
  const arch = input.arch ?? detectArch();
  const installChannel = resolveInstallChannel(input.installChannel, env);
  const installRef = input.installRef ?? (await shell.resolveInstallRef(installChannel, input.version ?? env.HERMES_FLY_VERSION));
  const preparedSource = await shell.prepareInstallSource(installRef);

  try {
    await shell.ensureRuntimeArtifacts(preparedSource.sourceDir);
    const existingInstall = await shell.resolveExistingInstall({
      platform,
      homeDir,
      xdgDataHome: env.XDG_DATA_HOME,
      preferSystemInstall: userId === 0,
    });
    const installPaths = resolveInstallerPaths({
      platform,
      homeDir,
      xdgDataHome: env.XDG_DATA_HOME,
      preferSystemInstall: userId === 0,
      explicitInstallHome: input.installHome,
      explicitBinDir: input.binDir,
      envInstallHome: env.HERMES_FLY_HOME,
      envBinDir: env.HERMES_FLY_INSTALL_DIR,
      existingInstallHome: existingInstall?.installHome,
      existingBinDir: existingInstall?.binDir,
    });
    const plan = InstallerPlan.create({
      platform,
      arch,
      installChannel,
      installMethod: input.installMethod ?? preparedSource.installMethod,
      installRef,
      installHome: installPaths.installHome,
      binDir: installPaths.binDir,
      sourceDir: input.sourceDir ?? preparedSource.sourceDir,
    });

    return await sessionRunner(plan, { shell });
  } finally {
    preparedSource.cleanup();
  }
}

export function buildInstallerProgram(runInstall: InstallCommandHandler = async (input) => await runInstallCommand(input)): Command {
  const program = new Command()
    .name("hermes-fly-installer")
    .description("Hermes Fly installer")
    .helpOption("-h, --help", "Show help");

  program
    .command("install")
    .description("Install Hermes Fly")
    .option("--platform <platform>", "Override detected platform")
    .option("--arch <arch>", "Override detected architecture")
    .option("--channel <channel>", "Install channel")
    .option("--method <method>", "Internal install method override")
    .option("--ref <ref>", "Resolved install ref override")
    .option("--version <version>", "Requested version override")
    .option("--install-home <path>", "Install home override")
    .option("--bin-dir <path>", "Binary directory override")
    .option("--source-dir <path>", "Prepared source directory override")
    .action(async (opts: Record<string, string | undefined>) => {
      process.exitCode = await runInstall({
        platform: opts.platform,
        arch: opts.arch,
        installChannel: opts.channel as InstallChannel | undefined,
        installMethod: opts.method as InstallMethod | undefined,
        installRef: opts.ref,
        installHome: opts.installHome,
        binDir: opts.binDir,
        sourceDir: opts.sourceDir,
        version: opts.version,
      });
    });

  return program;
}

function normalizeInstallerUserArgs(argv: string[]): string[] {
  const userArgs = argv.slice(2);
  if (userArgs.length === 0) {
    return ["install"];
  }
  if (userArgs[0]?.startsWith("-")) {
    return ["install", ...userArgs];
  }
  return userArgs;
}

export async function runInstaller(argv: string[], program: Command = buildInstallerProgram()): Promise<void> {
  await program.parseAsync(normalizeInstallerUserArgs(argv), { from: "user" });
}

export function isInstallerEntrypoint(importMetaUrl: string, argv1?: string): boolean {
  if (!argv1) {
    return false;
  }

  try {
    return realpathSync(fileURLToPath(importMetaUrl)) === realpathSync(argv1);
  } catch {
    return fileURLToPath(importMetaUrl) === argv1;
  }
}

if (isInstallerEntrypoint(import.meta.url, process.argv[1])) {
  runInstaller(process.argv).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`Installer error: ${message}\n`);
    process.exitCode = 1;
  });
}
