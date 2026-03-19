import assert from "node:assert/strict";
import test from "node:test";
import { InstallerPlan } from "../../src/contexts/installer/domain/install-plan.ts";
import { runInstallSession } from "../../src/contexts/installer/application/use-cases/run-install-session.ts";
import type { InstallerShellPort } from "../../src/contexts/installer/application/ports/installer-shell.port.ts";

function createPlan(): InstallerPlan {
  return InstallerPlan.create({
    platform: "darwin",
    arch: "arm64",
    installChannel: "latest",
    installMethod: "release_asset",
    installRef: "v0.1.95",
    installHome: "/usr/local/lib/hermes-fly",
    binDir: "/usr/local/bin",
    sourceDir: "/tmp/hermes-fly",
  });
}

function createShell(overrides: Partial<InstallerShellPort> = {}): InstallerShellPort {
  return {
    readCommandVersion: async (command) => (command === "node" ? "v22.20.0" : "11.11.1"),
    readCommandPath: async (command) => `/.sprite/bin/${command}`,
    requiresSudo: async () => true,
    installFiles: async () => undefined,
    verifyInstalledVersion: async () => undefined,
    readInstalledVersion: async () => "hermes-fly 0.1.95",
    ...overrides,
  };
}

test("runInstallSession renders the redesigned installer flow and PATH guidance", async () => {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const code = await runInstallSession(createPlan(), {
    shell: createShell(),
    stdout: { write: (chunk: string) => { stdout.push(chunk); } },
    stderr: { write: (chunk: string) => { stderr.push(chunk); } },
    env: {
      PATH: "/usr/bin:/bin",
      SHELL: "/bin/zsh",
    },
  });

  assert.equal(code, 0);
  assert.equal(stderr.join(""), "");

  const output = stdout.join("");
  assert.match(output, /🪽 Hermes Fly Installer/);
  assert.match(output, /Install plan/);
  assert.match(output, /OS: darwin/);
  assert.match(output, /Arch: arm64/);
  assert.match(output, /Install method: packaged release asset/);
  assert.match(output, /Requested version: v0\.1\.95/);
  assert.match(output, /\[1\/3\] Preparing environment/);
  assert.match(output, /\[2\/3\] Installing Hermes Fly/);
  assert.match(output, /\[3\/3\] Finalizing setup/);
  assert.match(output, /✓ Node\.js v22\.20\.0 found/);
  assert.match(output, /· Active npm: 11\.11\.1 \(\/\.sprite\/bin\/npm\)/);
  assert.match(output, /! Elevated permissions required for \/usr\/local\/lib\/hermes-fly/);
  assert.match(output, /! PATH missing installer bin dir: \/usr\/local\/bin/);
  assert.match(output, /Fix \(zsh: ~\/\.zshrc, bash: ~\/\.bashrc\):/);
  assert.match(output, /export PATH="\/usr\/local\/bin:\$PATH"/);
  assert.match(output, /🪽 hermes-fly installed successfully \(hermes-fly 0\.1\.95\)!/);
});

test("runInstallSession surfaces install failures without hiding the error", async () => {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const code = await runInstallSession(createPlan(), {
    shell: createShell({
      installFiles: async () => {
        throw new Error("Cannot write to /usr/local/lib/hermes-fly");
      },
    }),
    stdout: { write: (chunk: string) => { stdout.push(chunk); } },
    stderr: { write: (chunk: string) => { stderr.push(chunk); } },
    env: {
      PATH: "/usr/local/bin:/usr/bin:/bin",
      SHELL: "/bin/bash",
    },
  });

  assert.equal(code, 1);
  assert.match(stdout.join(""), /\[2\/3\] Installing Hermes Fly/);
  assert.match(stderr.join(""), /Error: Cannot write to \/usr\/local\/lib\/hermes-fly/);
});
