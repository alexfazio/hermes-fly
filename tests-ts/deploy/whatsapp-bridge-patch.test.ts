import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { copyFile, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { describe, it } from "node:test";

const execFileAsync = promisify(execFile);

describe("patch-whatsapp-bridge.py", () => {
  it("patches the pinned upstream WhatsApp bridge fixture and stays idempotent", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-whatsapp-bridge-patch-"));
    const fixturePath = join(process.cwd(), "tests", "fixtures", "whatsapp-bridge.upstream.js");
    const scriptPath = join(process.cwd(), "templates", "patch-whatsapp-bridge.py");
    const bridgePath = join(root, "bridge.js");

    try {
      await copyFile(fixturePath, bridgePath);

      const before = await readFile(bridgePath, "utf8");
      await execFileAsync("python3", [scriptPath, bridgePath]);
      const after = await readFile(bridgePath, "utf8");

      assert.notEqual(after, before);
      assert.match(after, /function logBridgeDiagnostic/);
      assert.match(after, /messages\.upsert\.accepted/);
      assert.match(after, /messages\.upsert\.queued/);
      assert.match(after, /messages\.poll\.drained/);
      assert.match(after, /reason: 'missing-message-payload'/);

      await execFileAsync("python3", [scriptPath, bridgePath]);
      const afterAgain = await readFile(bridgePath, "utf8");
      assert.equal(afterAgain, after);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
