import assert from "node:assert/strict";
import test from "node:test";
import {
  INSTALL_MARKER_FILENAME,
  isReusableManagedInstallLayout,
  isKnownManagedInstallLayout,
  isSystemManagedInstallLayout,
  isUserLocalManagedInstallLayout,
  LEGACY_SYSTEM_BIN_DIR,
  LEGACY_SYSTEM_INSTALL_HOME,
  resolveKnownManagedInstallLayouts,
} from "../../src/contexts/installer/domain/managed-install-layout.ts";

test("resolveKnownManagedInstallLayouts includes the legacy system and user-local layouts", () => {
  assert.equal(INSTALL_MARKER_FILENAME, ".hermes-fly-install-managed");
  assert.deepEqual(resolveKnownManagedInstallLayouts("/Users/alex"), [
    {
      installHome: "/Users/alex/Library/Application Support/hermes-fly",
      binDir: "/Users/alex/.local/bin",
    },
    {
      installHome: "/Users/alex/.local/share/hermes-fly",
      binDir: "/Users/alex/.local/bin",
    },
    {
      installHome: "/Users/alex/.local/lib/hermes-fly",
      binDir: "/Users/alex/.local/bin",
    },
    {
      installHome: LEGACY_SYSTEM_INSTALL_HOME,
      binDir: LEGACY_SYSTEM_BIN_DIR,
    },
  ]);
});

test("resolveKnownManagedInstallLayouts includes Linux user-local data layouts, including XDG overrides", () => {
  assert.deepEqual(resolveKnownManagedInstallLayouts("/home/sprite", {
    userInstallHome: "/srv/hermes-data/hermes-fly",
  }), [
    {
      installHome: "/srv/hermes-data/hermes-fly",
      binDir: "/home/sprite/.local/bin",
    },
    {
      installHome: "/home/sprite/Library/Application Support/hermes-fly",
      binDir: "/home/sprite/.local/bin",
    },
    {
      installHome: "/home/sprite/.local/share/hermes-fly",
      binDir: "/home/sprite/.local/bin",
    },
    {
      installHome: "/home/sprite/.local/lib/hermes-fly",
      binDir: "/home/sprite/.local/bin",
    },
    {
      installHome: LEGACY_SYSTEM_INSTALL_HOME,
      binDir: LEGACY_SYSTEM_BIN_DIR,
    },
  ]);
});

test("isKnownManagedInstallLayout recognizes exact legacy managed layouts only", () => {
  assert.equal(
    isKnownManagedInstallLayout(
      {
        installHome: "/Users/alex/.local/lib/hermes-fly",
        binDir: "/Users/alex/.local/bin",
      },
      "/Users/alex",
    ),
    true,
  );

  assert.equal(
    isKnownManagedInstallLayout(
      {
        installHome: "/home/sprite/.local/share/hermes-fly",
        binDir: "/home/sprite/.local/bin",
      },
      "/home/sprite",
    ),
    true,
  );

  assert.equal(
    isKnownManagedInstallLayout(
      {
        installHome: "/srv/hermes-data/hermes-fly",
        binDir: "/home/sprite/.local/bin",
      },
      "/home/sprite",
      { userInstallHome: "/srv/hermes-data/hermes-fly" },
    ),
    true,
  );

  assert.equal(
    isKnownManagedInstallLayout(
      {
        installHome: "/Users/alex/Library/Application Support/hermes-fly",
        binDir: "/Users/alex/.local/bin",
      },
      "/Users/alex",
    ),
    true,
  );

  assert.equal(
    isKnownManagedInstallLayout(
      {
        installHome: "/Users/alex/custom/hermes-fly",
        binDir: "/Users/alex/.local/bin",
      },
      "/Users/alex",
    ),
    false,
  );
});

test("isSystemManagedInstallLayout recognizes only the legacy system layout", () => {
  assert.equal(
    isSystemManagedInstallLayout({
      installHome: LEGACY_SYSTEM_INSTALL_HOME,
      binDir: LEGACY_SYSTEM_BIN_DIR,
    }),
    true,
  );

  assert.equal(
    isSystemManagedInstallLayout({
      installHome: "/Users/alex/.local/lib/hermes-fly",
      binDir: "/Users/alex/.local/bin",
    }),
    false,
  );
});

test("isUserLocalManagedInstallLayout recognizes active legacy user-local layouts", () => {
  assert.equal(
    isUserLocalManagedInstallLayout(
      {
        installHome: "/home/alice/.local/lib/hermes-fly",
        binDir: "/home/alice/.local/bin",
      },
      {
        homeDir: "/home/alice",
      },
    ),
    true,
  );
});

test("isUserLocalManagedInstallLayout recognizes the active XDG-resolved user layout", () => {
  assert.equal(
    isUserLocalManagedInstallLayout(
      {
        installHome: "/srv/alice-xdg/hermes-fly",
        binDir: "/home/alice/.local/bin",
      },
      {
        homeDir: "/home/alice",
        userInstallHome: "/srv/alice-xdg/hermes-fly",
        userBinDir: "/home/alice/.local/bin",
      },
    ),
    true,
  );
});

test("isUserLocalManagedInstallLayout does not treat staged .local prefixes as the active user-local install", () => {
  assert.equal(
    isUserLocalManagedInstallLayout(
      {
        installHome: "/opt/stage/.local/share/hermes-fly",
        binDir: "/opt/stage/.local/bin",
      },
      {
        homeDir: "/home/alice",
        userInstallHome: "/srv/alice-xdg/hermes-fly",
        userBinDir: "/home/alice/.local/bin",
      },
    ),
    false,
  );
});

test("resolveKnownManagedInstallLayouts still exposes the legacy system layout when homeDir is unavailable", () => {
  assert.deepEqual(resolveKnownManagedInstallLayouts(undefined), [
    {
      installHome: LEGACY_SYSTEM_INSTALL_HOME,
      binDir: LEGACY_SYSTEM_BIN_DIR,
    },
  ]);
});

test("isReusableManagedInstallLayout accepts pre-marker custom installs that look like installed runtime layouts", () => {
  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/opt/hermes-fly",
          binDir: "/opt/hermes-bin",
        },
        hasInstallerMarker: false,
        hasCliEntrypoint: true,
        hasLegacyLibDirectory: false,
        hasPackageManifest: true,
        hasPackageLock: true,
        hasCommanderDependency: true,
        isRepoCheckout: false,
      },
      "/Users/alex",
    ),
    true,
  );

  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/opt/hermes-fly",
          binDir: "/opt/hermes-bin",
        },
        hasInstallerMarker: false,
        hasCliEntrypoint: true,
        hasLegacyLibDirectory: false,
        hasPackageManifest: false,
        hasPackageLock: true,
        hasCommanderDependency: true,
        isRepoCheckout: false,
      },
      "/Users/alex",
    ),
    false,
  );
});

test("isReusableManagedInstallLayout accepts legacy lib-based installs in known managed layouts", () => {
  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/Users/alex/.local/lib/hermes-fly",
          binDir: "/Users/alex/.local/bin",
        },
        hasInstallerMarker: false,
        hasCliEntrypoint: false,
        hasPackageManifest: false,
        hasPackageLock: false,
        hasCommanderDependency: false,
        hasLegacyLibDirectory: true,
        isRepoCheckout: false,
      },
      "/Users/alex",
    ),
    true,
  );
});

test("isReusableManagedInstallLayout accepts Linux user-local share installs in known managed layouts", () => {
  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/home/sprite/.local/share/hermes-fly",
          binDir: "/home/sprite/.local/bin",
        },
        hasInstallerMarker: true,
        hasCliEntrypoint: true,
        hasPackageManifest: false,
        hasPackageLock: false,
        hasCommanderDependency: false,
        hasLegacyLibDirectory: false,
        isRepoCheckout: false,
      },
      "/home/sprite",
    ),
    true,
  );
});

test("isReusableManagedInstallLayout accepts known managed layouts with a built CLI even without a launcher signal", () => {
  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/Users/alex/.local/lib/hermes-fly",
          binDir: "/Users/alex/.local/bin",
        },
        hasInstallerMarker: false,
        hasCliEntrypoint: true,
        hasPackageManifest: false,
        hasPackageLock: false,
        hasCommanderDependency: false,
        hasLegacyLibDirectory: false,
        isRepoCheckout: false,
      },
      "/Users/alex",
    ),
    true,
  );
});

test("isReusableManagedInstallLayout rejects legacy lib-based custom installs without a stronger ownership signal", () => {
  assert.equal(
    isReusableManagedInstallLayout(
      {
        layout: {
          installHome: "/opt/hermes-fly",
          binDir: "/opt/hermes-bin",
        },
        hasInstallerMarker: false,
        hasCliEntrypoint: false,
        hasPackageManifest: false,
        hasPackageLock: false,
        hasCommanderDependency: false,
        hasLegacyLibDirectory: true,
        isRepoCheckout: false,
      },
      "/Users/alex",
    ),
    false,
  );
});
