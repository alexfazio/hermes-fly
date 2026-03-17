import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import type { DeployConfig } from "../../src/contexts/deploy/application/ports/deploy-wizard.port.ts";
import { TemplateWriter } from "../../src/contexts/deploy/infrastructure/adapters/template-writer.ts";

const DEFAULT_CONFIG: DeployConfig = {
  orgSlug: "personal",
  appName: "test-app",
  region: "fra",
  vmSize: "shared-cpu-2x",
  volumeSize: 5,
  provider: "openrouter",
  apiKey: "sk-test",
  model: "anthropic/claude-sonnet-4-20250514",
  channel: "stable",
  hermesRef: "8eefbef91cd715cfe410bba8c13cfab4eb3040df",
  botToken: ""
};

describe("TemplateWriter", () => {
  it("renders the checked-in Dockerfile and fly.toml templates into the build context", async () => {
    const buildDir = await mkdtemp(join(tmpdir(), "hermes-template-writer-"));
    const writer = new TemplateWriter();

    try {
      await writer.createBuildContext(DEFAULT_CONFIG, buildDir);

      const dockerfile = await readFile(join(buildDir, "Dockerfile"), "utf8");
      const flyToml = await readFile(join(buildDir, "fly.toml"), "utf8");
      const entrypoint = await readFile(join(buildDir, "entrypoint.sh"), "utf8");

      assert.match(dockerfile, /^FROM python:3\.11-slim/m);
      assert.match(dockerfile, /^ARG HERMES_VERSION=8eefbef91cd715cfe410bba8c13cfab4eb3040df$/m);
      assert.match(dockerfile, /raw\.githubusercontent\.com\/NousResearch\/hermes-agent\/\$\{HERMES_VERSION\}\/scripts\/install\.sh/);
      assert.doesNotMatch(dockerfile, /ghcr\.io\/anthropics\/hermes-agent/);
      assert.match(dockerfile, /io\.hermes\.deploy\.channel="stable"/);
      assert.match(dockerfile, /io\.hermes\.compatibility_policy="1\.0\.0"/);

      assert.match(flyToml, /^app = "test-app"$/m);
      assert.match(flyToml, /^primary_region = "fra"$/m);
      assert.match(flyToml, /^\s*size = "shared-cpu-2x"$/m);
      assert.match(flyToml, /^\s*memory = "512"$/m);
      assert.match(flyToml, /^\s*source = "hermes_data"$/m);
      assert.match(flyToml, /^\s*destination = "\/root\/\.hermes"$/m);
      assert.match(flyToml, /^\s*initial_size = "5"$/m);
      assert.doesNotMatch(flyToml, /^\[http_service\]$/m);
      assert.doesNotMatch(flyToml, /internal_port = 8080/);

      assert.match(entrypoint, /exec \/opt\/hermes\/hermes-agent\/venv\/bin\/hermes gateway run/);
    } finally {
      await rm(buildDir, { recursive: true, force: true });
    }
  });
});
