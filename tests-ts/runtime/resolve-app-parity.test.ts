import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { resolveApp } from "../../src/commands/resolve-app.ts";

// Parity tests matching Bash lib/config.sh:235-264 behavior

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
