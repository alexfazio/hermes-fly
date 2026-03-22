import { realpathSync } from "node:fs";
import { join } from "node:path";

export interface ManagedInstallLayout {
  installHome: string;
  binDir: string;
}

export interface ManagedInstallProbe {
  layout: ManagedInstallLayout;
  hasInstallerMarker: boolean;
  hasCliEntrypoint: boolean;
  hasLegacyLibDirectory: boolean;
  hasPackageManifest: boolean;
  hasPackageLock: boolean;
  hasCommanderDependency: boolean;
  isRepoCheckout: boolean;
}

export interface ManagedInstallLayoutOptions {
  userInstallHome?: string;
  userBinDir?: string;
  systemInstallHome?: string;
  systemBinDir?: string;
}

export const INSTALL_MARKER_FILENAME = ".hermes-fly-install-managed";
export const LEGACY_SYSTEM_INSTALL_HOME = "/usr/local/lib/hermes-fly";
export const LEGACY_SYSTEM_BIN_DIR = "/usr/local/bin";

function requireNonEmptyValue(value: string, label: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${label} must be non-empty`);
  }
  return trimmed;
}

function normalizeComparablePath(pathValue: string, label: string): string {
  const normalizedPath = requireNonEmptyValue(pathValue, label);
  try {
    return realpathSync(normalizedPath);
  } catch {
    return normalizedPath;
  }
}

function normalizeHomeDir(homeDir?: string): string | undefined {
  const trimmedHomeDir = homeDir?.trim();
  if (!trimmedHomeDir) {
    return undefined;
  }

  const normalizedHomeDir = requireNonEmptyValue(trimmedHomeDir, "homeDir");
  try {
    return realpathSync(normalizedHomeDir);
  } catch {
    return normalizedHomeDir;
  }
}

function resolveSystemInstallLayout(options: ManagedInstallLayoutOptions = {}): ManagedInstallLayout {
  return {
    installHome: requireNonEmptyValue(options.systemInstallHome ?? LEGACY_SYSTEM_INSTALL_HOME, "systemInstallHome"),
    binDir: requireNonEmptyValue(options.systemBinDir ?? LEGACY_SYSTEM_BIN_DIR, "systemBinDir"),
  };
}

function resolveUserBinDir(normalizedHomeDir: string | undefined, options: ManagedInstallLayoutOptions = {}): string | undefined {
  const explicitUserBinDir = options.userBinDir?.trim();
  if (explicitUserBinDir) {
    return requireNonEmptyValue(explicitUserBinDir, "userBinDir");
  }
  if (!normalizedHomeDir) {
    return undefined;
  }
  return join(normalizedHomeDir, ".local", "bin");
}

function appendUniqueLayout(target: ManagedInstallLayout[], layout: ManagedInstallLayout | undefined): void {
  if (!layout) {
    return;
  }

  const installHome = normalizeComparablePath(layout.installHome, "layout.installHome");
  const binDir = normalizeComparablePath(layout.binDir, "layout.binDir");
  const alreadyPresent = target.some((candidate) =>
    normalizeComparablePath(candidate.installHome, "candidate.installHome") === installHome
    && normalizeComparablePath(candidate.binDir, "candidate.binDir") === binDir,
  );
  if (!alreadyPresent) {
    target.push({ installHome, binDir });
  }
}

interface UserLocalManagedInstallLayoutContext extends Pick<ManagedInstallLayoutOptions, "userInstallHome" | "userBinDir"> {
  homeDir?: string;
}

function resolveCurrentUserLocalManagedInstallLayouts(
  homeDir?: string,
  options: Pick<ManagedInstallLayoutOptions, "userInstallHome" | "userBinDir"> = {},
): ManagedInstallLayout[] {
  const normalizedHomeDir = normalizeHomeDir(homeDir);
  const userBinDir = resolveUserBinDir(normalizedHomeDir, options);
  const layouts: ManagedInstallLayout[] = [];

  const explicitUserInstallHome = options.userInstallHome?.trim();
  if (explicitUserInstallHome && userBinDir) {
    appendUniqueLayout(layouts, {
      installHome: requireNonEmptyValue(explicitUserInstallHome, "userInstallHome"),
      binDir: userBinDir,
    });
  }

  if (!normalizedHomeDir || !userBinDir) {
    return layouts;
  }

  appendUniqueLayout(layouts, {
    installHome: join(normalizedHomeDir, "Library", "Application Support", "hermes-fly"),
    binDir: userBinDir,
  });
  appendUniqueLayout(layouts, {
    installHome: join(normalizedHomeDir, ".local", "share", "hermes-fly"),
    binDir: userBinDir,
  });
  appendUniqueLayout(layouts, {
    installHome: join(normalizedHomeDir, ".local", "lib", "hermes-fly"),
    binDir: userBinDir,
  });

  return layouts;
}

export function resolveKnownManagedInstallLayouts(homeDir?: string, options: ManagedInstallLayoutOptions = {}): ManagedInstallLayout[] {
  const normalizedHomeDir = normalizeHomeDir(homeDir);
  const userBinDir = resolveUserBinDir(normalizedHomeDir, options);
  const systemLayout = resolveSystemInstallLayout(options);
  const knownLayouts: ManagedInstallLayout[] = [];

  if (normalizedHomeDir && userBinDir) {
    const explicitUserInstallHome = options.userInstallHome?.trim();
    if (explicitUserInstallHome) {
      appendUniqueLayout(knownLayouts, {
        installHome: requireNonEmptyValue(explicitUserInstallHome, "userInstallHome"),
        binDir: userBinDir,
      });
    }

    appendUniqueLayout(knownLayouts, {
      installHome: join(normalizedHomeDir, "Library", "Application Support", "hermes-fly"),
      binDir: userBinDir,
    });
    appendUniqueLayout(knownLayouts, {
      installHome: join(normalizedHomeDir, ".local", "share", "hermes-fly"),
      binDir: userBinDir,
    });
    appendUniqueLayout(knownLayouts, {
      installHome: join(normalizedHomeDir, ".local", "lib", "hermes-fly"),
      binDir: userBinDir,
    });
  }

  appendUniqueLayout(knownLayouts, systemLayout);
  return knownLayouts;
}

export function isKnownManagedInstallLayout(
  layout: ManagedInstallLayout,
  homeDir?: string,
  options: ManagedInstallLayoutOptions = {},
): boolean {
  const installHome = normalizeComparablePath(layout.installHome, "layout.installHome");
  const binDir = normalizeComparablePath(layout.binDir, "layout.binDir");

  return resolveKnownManagedInstallLayouts(homeDir, options).some((candidate) =>
    normalizeComparablePath(candidate.installHome, "candidate.installHome") === installHome
    && normalizeComparablePath(candidate.binDir, "candidate.binDir") === binDir,
  );
}

export function isSystemManagedInstallLayout(
  layout: ManagedInstallLayout,
  options: ManagedInstallLayoutOptions = {},
): boolean {
  const installHome = normalizeComparablePath(layout.installHome, "layout.installHome");
  const binDir = normalizeComparablePath(layout.binDir, "layout.binDir");
  const systemLayout = resolveSystemInstallLayout(options);

  return normalizeComparablePath(systemLayout.installHome, "systemLayout.installHome") === installHome
    && normalizeComparablePath(systemLayout.binDir, "systemLayout.binDir") === binDir;
}

export function isUserLocalManagedInstallLayout(
  layout: ManagedInstallLayout,
  context: UserLocalManagedInstallLayoutContext = {},
): boolean {
  const installHome = normalizeComparablePath(layout.installHome, "layout.installHome");
  const binDir = normalizeComparablePath(layout.binDir, "layout.binDir");

  return resolveCurrentUserLocalManagedInstallLayouts(context.homeDir, context).some((candidate) =>
    normalizeComparablePath(candidate.installHome, "candidate.installHome") === installHome
    && normalizeComparablePath(candidate.binDir, "candidate.binDir") === binDir,
  );
}

export function isReusableManagedInstallLayout(
  probe: ManagedInstallProbe,
  homeDir?: string,
  options: ManagedInstallLayoutOptions = {},
): boolean {
  const layout = {
    installHome: requireNonEmptyValue(probe.layout.installHome, "probe.layout.installHome"),
    binDir: requireNonEmptyValue(probe.layout.binDir, "probe.layout.binDir"),
  };

  if (probe.isRepoCheckout) {
    return false;
  }
  const isKnownLayout = isKnownManagedInstallLayout(layout, homeDir, options);
  if (probe.hasCliEntrypoint && probe.hasInstallerMarker) {
    return true;
  }
  if (probe.hasCliEntrypoint && isKnownLayout) {
    return true;
  }
  if (probe.hasCliEntrypoint) {
    return probe.hasPackageManifest && probe.hasPackageLock && probe.hasCommanderDependency;
  }
  return probe.hasLegacyLibDirectory && isKnownLayout;
}
