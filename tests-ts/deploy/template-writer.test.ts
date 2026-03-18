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
      const sitecustomize = await readFile(join(buildDir, "sitecustomize.py"), "utf8");
      const patchBridge = await readFile(join(buildDir, "patch-whatsapp-bridge.py"), "utf8");

      assert.match(dockerfile, /^FROM python:3\.11-slim/m);
      assert.match(dockerfile, /^ARG HERMES_VERSION=8eefbef91cd715cfe410bba8c13cfab4eb3040df$/m);
      assert.match(dockerfile, /raw\.githubusercontent\.com\/NousResearch\/hermes-agent\/\$\{HERMES_VERSION\}\/scripts\/install\.sh/);
      assert.doesNotMatch(dockerfile, /ghcr\.io\/anthropics\/hermes-agent/);
      assert.match(dockerfile, /io\.hermes\.deploy\.channel="stable"/);
      assert.match(dockerfile, /io\.hermes\.compatibility_policy="1\.0\.0"/);
      assert.match(dockerfile, /COPY patch-whatsapp-bridge\.py \/tmp\/hermes-fly-patch-whatsapp-bridge\.py/);
      assert.match(dockerfile, /hermes-fly-patch-whatsapp-bridge\.py \/opt\/hermes\/hermes-agent\/scripts\/whatsapp-bridge\/bridge\.js/);

      assert.match(flyToml, /^app = "test-app"$/m);
      assert.match(flyToml, /^primary_region = "fra"$/m);
      assert.match(flyToml, /^\s*size = "shared-cpu-2x"$/m);
      assert.match(flyToml, /^\s*memory = "512"$/m);
      assert.match(flyToml, /^\s*source = "hermes_data"$/m);
      assert.match(flyToml, /^\s*destination = "\/root\/\.hermes"$/m);
      assert.match(flyToml, /^\s*initial_size = "5"$/m);
      assert.doesNotMatch(flyToml, /^\[http_service\]$/m);
      assert.doesNotMatch(flyToml, /internal_port = 8080/);

      assert.match(entrypoint, /exec \/opt\/hermes\/hermes-agent\/venv\/bin\/hermes gateway run --replace/);
      assert.match(entrypoint, /\/root\/\.claude\/\.credentials\.json/);
      assert.match(entrypoint, /claudeAiOauth/);
      assert.match(entrypoint, /GLM_API_KEY/);
      assert.match(entrypoint, /GLM_BASE_URL/);
      assert.match(entrypoint, /HERMES_ZAI_THINKING/);
      assert.match(entrypoint, /DISCORD_BOT_TOKEN/);
      assert.match(entrypoint, /SLACK_BOT_TOKEN/);
      assert.match(entrypoint, /SLACK_APP_TOKEN/);
      assert.match(entrypoint, /HERMES_FLY_WHATSAPP_PENDING/);
      assert.match(entrypoint, /HERMES_FLY_WHATSAPP_MODE/);
      assert.match(entrypoint, /HERMES_FLY_WHATSAPP_ALLOWED_USERS/);
      assert.match(entrypoint, /find \/root\/\.hermes\/whatsapp\/session -mindepth 1/);
      assert.match(entrypoint, /if \[\[ -z "\$\{WHATSAPP_ENABLED:-\}" \]\]; then/);
      assert.match(entrypoint, /sed -i '\/\^WHATSAPP_ENABLED=\/d' \/root\/\.hermes\/\.env/);
      assert.match(entrypoint, /sed -i '\/\^WHATSAPP_MODE=\/d' \/root\/\.hermes\/\.env/);
      assert.match(entrypoint, /sed -i '\/\^WHATSAPP_ALLOWED_USERS=\/d' \/root\/\.hermes\/\.env/);

      assert.match(sitecustomize, /HERMES_ZAI_THINKING/);
      assert.match(sitecustomize, /thinking/);
      assert.match(sitecustomize, /disabled/);
      assert.match(sitecustomize, /run_agent/);

      assert.match(patchBridge, /messages\.upsert\.skipped/);
      assert.match(patchBridge, /messages\.upsert\.accepted/);
      assert.match(patchBridge, /messages\.poll\.drained/);
    } finally {
      await rm(buildDir, { recursive: true, force: true });
    }
  });
});
