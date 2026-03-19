import assert from "node:assert/strict";
import test from "node:test";
import { buildInstallerProgram, type InstallCommandInput } from "../../src/install-cli";

test("installer CLI registers the internal install command", () => {
  const program = buildInstallerProgram(async () => 0);
  const names = program.commands.map((command) => command.name());
  assert.deepEqual(names, ["install"]);
});

test("installer CLI parses install arguments into an install command request", async () => {
  const calls: InstallCommandInput[] = [];
  const program = buildInstallerProgram(async (plan) => {
    calls.push(plan);
    return 0;
  });

  await program.parseAsync(
    [
      "install",
      "--platform",
      "darwin",
      "--arch",
      "arm64",
      "--channel",
      "latest",
      "--method",
      "release_asset",
      "--ref",
      "v0.1.95",
      "--install-home",
      "/usr/local/lib/hermes-fly",
      "--bin-dir",
      "/usr/local/bin",
      "--source-dir",
      "/tmp/hermes-fly",
    ],
    { from: "user" },
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.platform, "darwin");
  assert.equal(calls[0]?.installMethod, "release_asset");
  assert.equal(calls[0]?.sourceDir, "/tmp/hermes-fly");
});
