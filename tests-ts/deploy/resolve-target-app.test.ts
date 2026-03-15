import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ResolveTargetAppUseCase } from "../../src/contexts/deploy/application/use-cases/resolve-target-app.ts";
import type { ConfigRepositoryPort } from "../../src/contexts/deploy/application/ports/config-repository.port.ts";

// Stub port
function makeConfigPort(currentApp: string | null): ConfigRepositoryPort {
  return {
    readCurrentApp: async () => currentApp
  };
}

describe("ResolveTargetAppUseCase", () => {
  it("returns explicit -a APP value", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort("fallback-app"));
    const result = await useCase.execute(["-a", "explicit-app"]);
    assert.equal(result, "explicit-app");
  });

  it("repeated -a uses last value", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort(null));
    const result = await useCase.execute(["-a", "first-app", "-a", "last-app"]);
    assert.equal(result, "last-app");
  });

  it("trailing -a with no value returns null", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort("fallback-app"));
    const result = await useCase.execute(["-a"]);
    assert.equal(result, null);
  });

  it("-a --unknown-flag treats flag as explicit app name", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort("fallback-app"));
    const result = await useCase.execute(["-a", "--unknown-flag"]);
    assert.equal(result, "--unknown-flag");
  });

  it("no -a flag falls back to current_app from config port", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort("config-app"));
    const result = await useCase.execute([]);
    assert.equal(result, "config-app");
  });

  it("no -a and no current_app returns null", async () => {
    const useCase = new ResolveTargetAppUseCase(makeConfigPort(null));
    const result = await useCase.execute([]);
    assert.equal(result, null);
  });
});
