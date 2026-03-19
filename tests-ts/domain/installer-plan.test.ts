import assert from "node:assert/strict";
import test from "node:test";
import { InstallerPlan } from "../../src/contexts/installer/domain/install-plan.ts";

test("InstallerPlan accepts valid input and trims string fields", () => {
  const plan = InstallerPlan.create({
    platform: "  darwin  ",
    arch: "  arm64  ",
    installChannel: "latest",
    installMethod: "release_asset",
    installRef: "  v0.1.95  ",
    installHome: "  /usr/local/lib/hermes-fly  ",
    binDir: "  /usr/local/bin  ",
    sourceDir: "  /tmp/hermes-fly  ",
  });

  assert.equal(plan.platform, "darwin");
  assert.equal(plan.arch, "arm64");
  assert.equal(plan.installChannel, "latest");
  assert.equal(plan.installMethod, "release_asset");
  assert.equal(plan.installRef, "v0.1.95");
  assert.equal(plan.installHome, "/usr/local/lib/hermes-fly");
  assert.equal(plan.binDir, "/usr/local/bin");
  assert.equal(plan.sourceDir, "/tmp/hermes-fly");
});

test("InstallerPlan rejects invalid channel, method, and empty paths", () => {
  assert.throws(
    () =>
      InstallerPlan.create({
        platform: "darwin",
        arch: "arm64",
        installChannel: "nightly" as never,
        installMethod: "release_asset",
        installRef: "v0.1.95",
        installHome: "/usr/local/lib/hermes-fly",
        binDir: "/usr/local/bin",
        sourceDir: "/tmp/hermes-fly",
      }),
    /InstallerPlan\.installChannel must be one of latest\|stable\|preview\|edge/,
  );

  assert.throws(
    () =>
      InstallerPlan.create({
        platform: "darwin",
        arch: "arm64",
        installChannel: "latest",
        installMethod: "pkg" as never,
        installRef: "v0.1.95",
        installHome: "/usr/local/lib/hermes-fly",
        binDir: "/usr/local/bin",
        sourceDir: "/tmp/hermes-fly",
      }),
    /InstallerPlan\.installMethod must be release_asset\|source_build/,
  );

  assert.throws(
    () =>
      InstallerPlan.create({
        platform: "darwin",
        arch: "arm64",
        installChannel: "latest",
        installMethod: "release_asset",
        installRef: "v0.1.95",
        installHome: "   ",
        binDir: "/usr/local/bin",
        sourceDir: "/tmp/hermes-fly",
      }),
    /InstallerPlan\.installHome must be non-empty/,
  );
});
