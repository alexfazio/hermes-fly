import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { ForegroundProcessRunner } from "../../src/adapters/process.ts";
import { FlyDeployWizard } from "../../src/contexts/deploy/infrastructure/adapters/fly-deploy-wizard.ts";
import type { DeployPromptPort } from "../../src/contexts/deploy/infrastructure/adapters/deploy-prompts.ts";
import type { QrCodeRendererPort } from "../../src/contexts/deploy/infrastructure/adapters/qr-code.ts";

function makeProcessRunner(
  impl: (
    command: string,
    args: string[],
  ) => Promise<{ stdout?: string; stderr?: string; exitCode: number }>,
): ForegroundProcessRunner {
  return {
    run: async (command, args) => {
      const result = await impl(command, args);
      if (
        command === "fly"
        && args[0] === "orgs"
        && args[1] === "list"
        && result.exitCode !== 0
        && (result.stdout ?? "") === ""
        && (result.stderr ?? "") === ""
      ) {
        return {
          stdout: JSON.stringify([{ name: "Personal", slug: "personal", type: "PERSONAL" }]),
          stderr: "",
          exitCode: 0,
        };
      }
      return {
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? "",
        exitCode: result.exitCode,
      };
    },
    runStreaming: async () => ({ exitCode: 0 }),
    runForeground: async () => ({ exitCode: 0 }),
  };
}

function makePromptPort(
  answers: string[],
): DeployPromptPort & { writes: string[]; asked: string[] } {
  const writes: string[] = [];
  const asked: string[] = [];
  return {
    writes,
    asked,
    isInteractive: () => true,
    write: (message: string) => { writes.push(message); },
    ask: async (message: string) => {
      asked.push(message);
      return answers.shift() ?? "";
    },
    askSecret: async (message: string) => {
      asked.push(message);
      return answers.shift() ?? "";
    },
    pause: async () => {},
  };
}

function makeQrRenderer(output = "[[QR]]"): QrCodeRendererPort {
  return {
    render: async () => output,
  };
}

describe("FlyDeployWizard sizing guidance", () => {
  it("does not offer Starter and defaults the guided flow to Standard", async () => {
    const prompts = makePromptPort([
      "my-app",
      "2",
      "2",
      "",
      "2",
      "1",
      "sk-live",
      "2",
      "1",
      "5",
      "y",
    ]);
    const runner = makeProcessRunner(async (command, args) => {
      if (command === "fly" && args[0] === "platform" && args[1] === "regions") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { code: "iad", name: "Ashburn, Virginia (US)" },
            { code: "fra", name: "Frankfurt, Germany" },
            { code: "lhr", name: "London, United Kingdom" },
          ]),
        };
      }
      if (command === "fly" && args[0] === "platform" && args[1] === "vm-sizes") {
        return {
          exitCode: 0,
          stdout: JSON.stringify([
            { name: "shared-cpu-1x", memory_mb: 256 },
            { name: "shared-cpu-2x", memory_mb: 512 },
            { name: "performance-1x", memory_mb: 2048 },
          ]),
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getMe"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: {
              id: 12345,
              is_bot: true,
              first_name: "Hermes Test Bot",
              username: "test_hermes_bot",
            },
          }),
        };
      }
      if (command === "curl" && args.some((value) => value.includes("api.telegram.org/bot123:abc/getUpdates"))) {
        return {
          exitCode: 0,
          stdout: JSON.stringify({
            ok: true,
            result: [
              {
                update_id: 1,
                message: {
                  chat: { id: 12345, type: "private" },
                  from: { id: 12345, is_bot: false },
                },
              },
            ],
          }),
        };
      }
      return { exitCode: 1, stdout: "", stderr: "" };
    });
    const wizard = new FlyDeployWizard({}, { prompts, process: runner, qrRenderer: makeQrRenderer() });

    const config = await wizard.collectConfig({ channel: "stable" });

    assert.equal(config.vmSize, "shared-cpu-2x");
    const copy = prompts.writes.join("");
    assert.match(copy, /How powerful should your agent's server be/);
    assert.ok(prompts.asked.includes("Choose a tier [1]: "));
    assert.match(copy, /Standard\s+512 MB/);
    assert.doesNotMatch(copy, /Starter\s+256 MB/);
  });
});
