import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { RunDeployWizardUseCase } from "../../src/contexts/deploy/application/use-cases/run-deploy-wizard.ts";
import type { DeployWizardPort, DeployConfig } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";

function makeIO() {
  const lines: string[] = [];
  return {
    stderr: { write: (s: string) => { lines.push(s); } },
    get text() { return lines.join(""); }
  };
}

const DEFAULT_CONFIG: DeployConfig = {
  appName: "test-app",
  region: "iad",
  vmSize: "shared-cpu-1x",
  volumeSize: 5,
  apiKey: "sk-test",
  model: "anthropic/claude-sonnet-4-20250514",
  channel: "stable",
  hermesRef: "8eefbef91cd715cfe410bba8c13cfab4eb3040df",
  botToken: ""
};

function makePort(overrides: Partial<DeployWizardPort> = {}): DeployWizardPort {
  return {
    checkPlatform: async () => ({ ok: true }),
    checkPrerequisites: async () => ({ ok: true }),
    checkAuth: async () => ({ ok: true }),
    checkConnectivity: async () => ({ ok: true }),
    collectConfig: async () => DEFAULT_CONFIG,
    createBuildContext: async () => ({ buildDir: "/tmp/test-build" }),
    provisionResources: async () => ({ ok: true }),
    runDeploy: async () => ({ ok: true }),
    postDeployCheck: async () => ({ ok: true }),
    saveApp: async () => {},
    ...overrides
  };
}

describe("RunDeployWizardUseCase - happy path", () => {
  it("returns ok when all phases pass", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort());
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "ok");
  });

  it("saves app after successful deploy", async () => {
    const saved: Array<{ appName: string; region: string }> = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      saveApp: async (appName, region) => { saved.push({ appName, region }); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(saved.length, 1);
    assert.equal(saved[0].appName, "test-app");
  });
});

describe("RunDeployWizardUseCase - preflight failure", () => {
  it("returns failed when platform check fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPlatform: async () => ({ ok: false, error: "Windows not supported" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("returns failed when prerequisites check fails with auto-install disabled", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async (opts) => opts.autoInstall
        ? { ok: true }
        : { ok: false, missing: "fly", autoInstallDisabled: true }
    }));
    const result = await uc.execute({ autoInstall: false, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("outputs auto-install disabled message when prereq check fails without auto-install", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async () => ({ ok: false, missing: "fly", autoInstallDisabled: true })
    }));
    await uc.execute({ autoInstall: false, channel: "stable" }, io.stderr);
    assert.ok(io.text.includes("auto-install disabled") || io.text.includes("fly"), `got: ${io.text}`);
  });
});

describe("RunDeployWizardUseCase - provision failure", () => {
  it("returns failed when provision fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      provisionResources: async () => ({ ok: false, error: "Name already taken" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });
});

describe("RunDeployWizardUseCase - deploy failure with resume hint", () => {
  it("returns failed when fly deploy fails", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({ ok: false, error: "deploy failed" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("saves app even when fly deploy fails (preserves resources)", async () => {
    const saved: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({ ok: false, error: "deploy failed" }),
      saveApp: async (appName) => { saved.push(appName); }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(saved.length, 1, "app should be saved even on deploy failure");
  });

  it("outputs resume hint after deploy failure", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      runDeploy: async () => ({ ok: false, error: "deploy failed" })
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.ok(io.text.includes("resume") || io.text.includes("hermes-fly resume"), `expected resume hint, got: ${io.text}`);
  });
});

describe("RunDeployWizardUseCase - missing OPENROUTER_API_KEY", () => {
  it("returns failed when OPENROUTER_API_KEY is missing", async () => {
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async () => ({ ok: false, missing: "OPENROUTER_API_KEY" })
    }));
    const result = await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(result.kind, "failed");
  });

  it("fails before provisioning when OPENROUTER_API_KEY is missing", async () => {
    const provisioned: boolean[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      checkPrerequisites: async () => ({ ok: false, missing: "OPENROUTER_API_KEY" }),
      provisionResources: async () => { provisioned.push(true); return { ok: true }; }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(provisioned.length, 0, "provisioning must not run when API key is missing");
  });
});

describe("RunDeployWizardUseCase - channel resolution", () => {
  it("passes stable channel to collectConfig", async () => {
    const captured: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async (opts) => {
        captured.push(opts.channel);
        return { ...DEFAULT_CONFIG, channel: opts.channel };
      }
    }));
    await uc.execute({ autoInstall: true, channel: "stable" }, io.stderr);
    assert.equal(captured[0], "stable");
  });

  it("normalizes invalid channel to stable", async () => {
    const captured: string[] = [];
    const io = makeIO();
    const uc = new RunDeployWizardUseCase(makePort({
      collectConfig: async (opts) => {
        captured.push(opts.channel);
        return { ...DEFAULT_CONFIG, channel: opts.channel };
      }
    }));
    await uc.execute({ autoInstall: true, channel: "invalid" as "stable" }, io.stderr);
    assert.equal(captured[0], "stable");
  });
});

import { FlyDeployWizard } from "../../src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("FlyDeployWizard.saveApp - persistence contract", () => {
  it("saveApp writes current_app and apps region entry", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "iad");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.ok(content.includes("current_app:"), `current_app: not found in:\n${content}`);
      assert.ok(content.includes("apps:"), `apps: not found in:\n${content}`);
      assert.ok(content.includes("- name:"), `- name: not found in:\n${content}`);
      assert.ok(content.includes("region:"), `region: not found in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  it("saveApp rewrites existing app entry without duplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-test-"));
    try {
      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "iad");
      await wizard.saveApp("my-app", "lax");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("FlyDeployWizard.saveApp - trailing lines preservation", () => {
  it("saveApp preserves non-target lines after apps section", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-trail-"));
    try {
      const { writeFile } = await import("node:fs/promises");
      const seed = [
        "current_app: old-app",
        "apps:",
        "  - name: old-app",
        "    region: ord",
        "metadata: keep-me",
      ].join("\n") + "\n";
      await writeFile(join(dir, "config.yaml"), seed, "utf8");

      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "iad");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      assert.ok(content.includes("metadata: keep-me"), `metadata lost:\n${content}`);
      assert.ok(content.includes("current_app: my-app"), `current_app wrong:\n${content}`);
      assert.ok(content.includes("  - name: my-app"), `name entry missing:\n${content}`);
      assert.ok(content.includes("    region: iad"), `region missing:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("FlyDeployWizard.saveApp - whitespace-normalized dedup", () => {
  it("saveApp dedupes app entries with whitespace-normalized names", async () => {
    const dir = await mkdtemp(join(tmpdir(), "saveapp-ws-"));
    try {
      const { writeFile } = await import("node:fs/promises");
      const seed = [
        "current_app: my-app",
        "apps:",
        "  - name: my-app   ",
        "    region: ord",
      ].join("\n") + "\n";
      await writeFile(join(dir, "config.yaml"), seed, "utf8");

      const wizard = new FlyDeployWizard({ HERMES_FLY_CONFIG_DIR: dir, HOME: dir });
      await wizard.saveApp("my-app", "lax");
      const content = await readFile(join(dir, "config.yaml"), "utf8");
      const nameMatches = (content.match(/  - name: my-app/g) ?? []).length;
      assert.equal(nameMatches, 1, `expected exactly 1 name entry, got ${nameMatches} in:\n${content}`);
      assert.ok(content.includes("region: lax"), `expected region lax in:\n${content}`);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});
