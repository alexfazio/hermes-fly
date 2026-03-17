import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { resolveApp, resolveApps } from "../../src/commands/resolve-app.ts";

// Parity tests matching original Bash config module resolve-app behavior

describe("resolve-app parity - explicit -a flag", () => {
  it("-a APP returns the explicit app name", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-a-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a", "explicit-app"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "explicit-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("repeated -a uses last value", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-repeat-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const app = await resolveApp(["-a", "first-app", "-a", "last-app"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "last-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("trailing -a with no value returns null", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-trail-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("-a --unknown-flag treats the flag as the app name", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-flag-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a", "--unknown-flag"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "--unknown-flag");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("resolve-app parity - current_app fallback", () => {
  it("bare positional app name wins over current_app from config.yaml", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-positional-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["explicit-app"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "explicit-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("no -a flag uses current_app from config.yaml", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-fallback-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp([], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, "fallback-app");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("no -a and missing config returns null", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-noconfig-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const app = await resolveApp([], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("trailing -a after valid value returns null ignoring config", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-trail2-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const app = await resolveApp(["-a", "first", "-a"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(app, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe("resolve-apps parity - batch destroy support", () => {
  it("returns all positional app names in order", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-apps-positional-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const apps = await resolveApps(["one", "two", "three"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.deepEqual(apps, ["one", "two", "three"]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns all repeated -a values in order", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-apps-explicit-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const apps = await resolveApps(["-a", "one", "-a", "two"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.deepEqual(apps, ["one", "two"]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("falls back to current_app as a singleton array", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-apps-fallback-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );
      const apps = await resolveApps([], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.deepEqual(apps, ["fallback-app"]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("returns null when -a is missing its value", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-parity-apps-missing-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const apps = await resolveApps(["-a"], {
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });
      assert.equal(apps, null);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
