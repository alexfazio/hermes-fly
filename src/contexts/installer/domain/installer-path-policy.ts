import { isAbsolute, join } from "node:path";
import {
  isUserLocalManagedInstallLayout,
  LEGACY_SYSTEM_BIN_DIR,
  LEGACY_SYSTEM_INSTALL_HOME,
} from "./managed-install-layout.js";

export interface ResolveInstallerPathsInput {
  platform: string;
  homeDir: string;
  xdgDataHome?: string;
  preferSystemInstall?: boolean;
  explicitInstallHome?: string;
  explicitBinDir?: string;
  envInstallHome?: string;
  envBinDir?: string;
  existingInstallHome?: string;
  existingBinDir?: string;
}

export interface InstallerPaths {
  installHome: string;
  binDir: string;
}

function resolveUserLocalLayoutContext(input: ResolveInstallerPathsInput): { homeDir?: string; userInstallHome?: string; userBinDir?: string } {
  const platform = readTrimmedValue(input.platform);
  const homeDir = readTrimmedValue(input.homeDir);
  if (!platform || !homeDir) {
    return {};
  }

  switch (platform) {
    case "linux":
    case "darwin":
      return {
        homeDir,
        userInstallHome: resolveDefaultInstallHome(platform, homeDir, input.xdgDataHome),
        userBinDir: resolveDefaultBinDir(homeDir),
      };
    default:
      return {};
  }
}

function readTrimmedValue(value?: string): string | undefined {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function resolveLinuxInstallHome(homeDir: string, xdgDataHome?: string): string {
  const xdgDataHomeValue = readTrimmedValue(xdgDataHome);
  const dataHome = xdgDataHomeValue && isAbsolute(xdgDataHomeValue)
    ? xdgDataHomeValue
    : join(homeDir, ".local", "share");
  return join(dataHome, "hermes-fly");
}

function resolveDefaultInstallHome(platform: string, homeDir: string, xdgDataHome?: string): string {
  switch (platform) {
    case "linux":
      return resolveLinuxInstallHome(homeDir, xdgDataHome);
    case "darwin":
      return join(homeDir, "Library", "Application Support", "hermes-fly");
    default:
      throw new Error(`Unsupported installer platform for path resolution: ${platform}`);
  }
}

function resolveDefaultBinDir(homeDir: string): string {
  return join(homeDir, ".local", "bin");
}

function resolveSystemInstallPaths(): InstallerPaths {
  return {
    installHome: LEGACY_SYSTEM_INSTALL_HOME,
    binDir: LEGACY_SYSTEM_BIN_DIR,
  };
}

export function resolveInstallerPaths(input: ResolveInstallerPathsInput): InstallerPaths {
  const platform = readTrimmedValue(input.platform);
  const homeDir = readTrimmedValue(input.homeDir);
  if (!platform) {
    throw new Error("ResolveInstallerPathsInput.platform must be non-empty");
  }
  if (!homeDir) {
    throw new Error("ResolveInstallerPathsInput.homeDir must be non-empty");
  }

  const explicitInstallHome = readTrimmedValue(input.explicitInstallHome);
  const explicitBinDir = readTrimmedValue(input.explicitBinDir);
  const envInstallHome = readTrimmedValue(input.envInstallHome);
  const envBinDir = readTrimmedValue(input.envBinDir);
  const existingInstallHome = readTrimmedValue(input.existingInstallHome);
  const existingBinDir = readTrimmedValue(input.existingBinDir);
  const userLocalLayoutContext = resolveUserLocalLayoutContext(input);
  const hasInstallOverride =
    explicitInstallHome !== undefined
    || explicitBinDir !== undefined
    || envInstallHome !== undefined
    || envBinDir !== undefined;
  const canReuseExistingLayout =
    !hasInstallOverride
    && existingInstallHome !== undefined
    && existingBinDir !== undefined
    && (
      input.preferSystemInstall !== true
      || !isUserLocalManagedInstallLayout({
        installHome: existingInstallHome,
        binDir: existingBinDir,
      }, userLocalLayoutContext)
    );

  return {
    installHome:
      explicitInstallHome
      ?? envInstallHome
      ?? (canReuseExistingLayout ? existingInstallHome : undefined)
      ?? (input.preferSystemInstall === true
        ? resolveSystemInstallPaths().installHome
        : resolveDefaultInstallHome(platform, homeDir, input.xdgDataHome)),
    binDir:
      explicitBinDir
      ?? envBinDir
      ?? (canReuseExistingLayout ? existingBinDir : undefined)
      ?? (input.preferSystemInstall === true
        ? resolveSystemInstallPaths().binDir
        : resolveDefaultBinDir(homeDir)),
  };
}
