import assert from "node:assert/strict";
import test from "node:test";
import { resolveInstallerPaths } from "../../src/contexts/installer/domain/installer-path-policy.ts";

test("resolveInstallerPaths uses Linux XDG defaults when no overrides are present", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/sprite",
  });

  assert.deepEqual(paths, {
    installHome: "/home/sprite/.local/share/hermes-fly",
    binDir: "/home/sprite/.local/bin",
  });
});

test("resolveInstallerPaths uses the legacy system layout for fresh privileged installs", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/root",
    preferSystemInstall: true,
  });

  assert.deepEqual(paths, {
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/usr/local/bin",
  });
});

test("resolveInstallerPaths uses macOS Application Support for install home", () => {
  const paths = resolveInstallerPaths({
    platform: "darwin",
    homeDir: "/Users/alex",
  });

  assert.deepEqual(paths, {
    installHome: "/Users/alex/Library/Application Support/hermes-fly",
    binDir: "/Users/alex/.local/bin",
  });
});

test("resolveInstallerPaths honors XDG_DATA_HOME for Linux install home", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/sprite",
    xdgDataHome: "/home/sprite/.xdg/data",
  });

  assert.equal(paths.installHome, "/home/sprite/.xdg/data/hermes-fly");
  assert.equal(paths.binDir, "/home/sprite/.local/bin");
});

test("resolveInstallerPaths ignores a relative XDG_DATA_HOME and falls back to the user-local data dir", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/sprite",
    xdgDataHome: "share",
  });

  assert.equal(paths.installHome, "/home/sprite/.local/share/hermes-fly");
  assert.equal(paths.binDir, "/home/sprite/.local/bin");
});

test("resolveInstallerPaths reuses an existing install when no overrides are provided", () => {
  const paths = resolveInstallerPaths({
    platform: "darwin",
    homeDir: "/Users/alex",
    existingInstallHome: "/usr/local/lib/hermes-fly",
    existingBinDir: "/usr/local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/usr/local/bin",
  });
});

test("resolveInstallerPaths gives explicit and environment overrides precedence over existing installs", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/sprite",
    envInstallHome: "/env/hermes-fly",
    existingInstallHome: "/usr/local/lib/hermes-fly",
    explicitBinDir: "/custom/bin",
    existingBinDir: "/usr/local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/env/hermes-fly",
    binDir: "/custom/bin",
  });
});

test("resolveInstallerPaths does not reuse an existing bin dir when install home is explicitly overridden", () => {
  const paths = resolveInstallerPaths({
    platform: "darwin",
    homeDir: "/Users/alex",
    explicitInstallHome: "/Users/alex/custom/hermes-fly",
    existingInstallHome: "/usr/local/lib/hermes-fly",
    existingBinDir: "/usr/local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/Users/alex/custom/hermes-fly",
    binDir: "/Users/alex/.local/bin",
  });
});

test("resolveInstallerPaths keeps system defaults for the missing side of a privileged partial override", () => {
  const installHomeOverride = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/root",
    preferSystemInstall: true,
    explicitInstallHome: "/opt/hermes-fly",
  });
  assert.deepEqual(installHomeOverride, {
    installHome: "/opt/hermes-fly",
    binDir: "/usr/local/bin",
  });

  const binDirOverride = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/root",
    preferSystemInstall: true,
    explicitBinDir: "/opt/hermes-bin",
  });
  assert.deepEqual(binDirOverride, {
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/opt/hermes-bin",
  });
});

test("resolveInstallerPaths does not reuse a user-local existing layout during a privileged install", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/alice",
    preferSystemInstall: true,
    existingInstallHome: "/home/alice/.local/lib/hermes-fly",
    existingBinDir: "/home/alice/.local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/usr/local/bin",
  });
});

test("resolveInstallerPaths still reuses staged .local prefixes during a privileged install", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/alice",
    preferSystemInstall: true,
    existingInstallHome: "/opt/stage/.local/share/hermes-fly",
    existingBinDir: "/opt/stage/.local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/opt/stage/.local/share/hermes-fly",
    binDir: "/opt/stage/.local/bin",
  });
});

test("resolveInstallerPaths does not reuse an existing XDG_DATA_HOME layout during a privileged install", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/alice",
    xdgDataHome: "/srv/alice-xdg",
    preferSystemInstall: true,
    existingInstallHome: "/srv/alice-xdg/hermes-fly",
    existingBinDir: "/home/alice/.local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/usr/local/bin",
  });
});

test("resolveInstallerPaths reuses a marked custom existing layout during a privileged install", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/root",
    preferSystemInstall: true,
    existingInstallHome: "/opt/hermes-fly",
    existingBinDir: "/opt/hermes-bin",
  });

  assert.deepEqual(paths, {
    installHome: "/opt/hermes-fly",
    binDir: "/opt/hermes-bin",
  });
});

test("resolveInstallerPaths accepts fully explicit destinations without resolving unsupported platform defaults", () => {
  const paths = resolveInstallerPaths({
    platform: "freebsd",
    homeDir: "/tmp/ignored",
    explicitInstallHome: "/opt/hermes-fly",
    explicitBinDir: "/opt/hermes-bin",
  });

  assert.deepEqual(paths, {
    installHome: "/opt/hermes-fly",
    binDir: "/opt/hermes-bin",
  });
});

test("resolveInstallerPaths does not reuse an existing install home when bin dir is explicitly overridden", () => {
  const paths = resolveInstallerPaths({
    platform: "linux",
    homeDir: "/home/sprite",
    explicitBinDir: "/home/sprite/bin",
    existingInstallHome: "/usr/local/lib/hermes-fly",
    existingBinDir: "/usr/local/bin",
  });

  assert.deepEqual(paths, {
    installHome: "/home/sprite/.local/share/hermes-fly",
    binDir: "/home/sprite/bin",
  });
});
