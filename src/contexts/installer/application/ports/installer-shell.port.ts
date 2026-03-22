import type { InstallChannel, InstallMethod, InstallerPlan } from "../../domain/install-plan.js";

export interface PreparedInstallSource {
  sourceDir: string;
  installMethod: InstallMethod;
  cleanup: () => void;
}

export interface ExistingInstallLocation {
  installHome: string;
  binDir: string;
}

export interface ResolveExistingInstallOptions {
  platform?: string;
  homeDir?: string;
  xdgDataHome?: string;
  preferSystemInstall?: boolean;
}

export interface InstallerShellPort {
  readCommandVersion(command: "node" | "npm"): Promise<string>;
  readCommandPath(command: string): Promise<string>;
  requiresSudo(installHome: string, binDir: string): Promise<boolean>;
  installFiles(plan: InstallerPlan): Promise<void>;
  verifyInstalledVersion(binaryPath: string, installRef: string): Promise<void>;
  readInstalledVersion(binaryPath: string): Promise<string>;
}

export interface InstallerBootstrapPort extends InstallerShellPort {
  resolveExistingInstall(options?: ResolveExistingInstallOptions): Promise<ExistingInstallLocation | null>;
  resolveInstallRef(channel: InstallChannel, requestedVersion?: string): Promise<string>;
  prepareInstallSource(installRef: string): Promise<PreparedInstallSource>;
  ensureRuntimeArtifacts(sourceDir: string): Promise<void>;
}
