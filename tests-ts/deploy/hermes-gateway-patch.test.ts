import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { describe, it } from "node:test";

const execFileAsync = promisify(execFile);

const BASE_FIXTURE = `from abc import ABC, abstractmethod
import asyncio

class BasePlatformAdapter(ABC):
    @abstractmethod
    async def send_typing(self, chat_id: str) -> None:
        raise NotImplementedError

    async def _keep_typing(self, chat_id: str, interval: float = 2.0) -> None:
        """
        Continuously send typing indicator until cancelled.
        """
        try:
            while True:
                await self.send_typing(chat_id)
                await asyncio.sleep(interval)
        except asyncio.CancelledError:
            pass  # Normal cancellation when handler completes
`;

const SIGNAL_FIXTURE = `class SignalPlatformAdapter:
    async def send_typing(self, chat_id: str) -> None:
        return None
`;

describe("patch-hermes-gateway.py", () => {
  it("patches the pinned Hermes gateway typing contract and stays idempotent", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-gateway-patch-"));
    const scriptPath = join(process.cwd(), "templates", "patch-hermes-gateway.py");
    const platformsDir = join(root, "gateway", "platforms");
    const basePath = join(platformsDir, "base.py");
    const signalPath = join(platformsDir, "signal.py");

    try {
      await mkdir(platformsDir, { recursive: true });
      await writeFile(basePath, BASE_FIXTURE, "utf8");
      await writeFile(signalPath, SIGNAL_FIXTURE, "utf8");

      const beforeBase = await readFile(basePath, "utf8");
      const beforeSignal = await readFile(signalPath, "utf8");

      await execFileAsync("python3", [scriptPath, root]);

      const afterBase = await readFile(basePath, "utf8");
      const afterSignal = await readFile(signalPath, "utf8");

      assert.notEqual(afterBase, beforeBase);
      assert.notEqual(afterSignal, beforeSignal);
      assert.match(afterBase, /async def send_typing\(self, chat_id: str, metadata=None\) -> None:/);
      assert.match(afterBase, /async def _keep_typing\(self, chat_id: str, interval: float = 2.0, metadata=None\) -> None:/);
      assert.match(afterBase, /await self\.send_typing\(chat_id, metadata=metadata\)/);
      assert.match(afterSignal, /async def send_typing\(self, chat_id: str, metadata=None\) -> None:/);

      await execFileAsync("python3", [scriptPath, root]);

      const afterAgainBase = await readFile(basePath, "utf8");
      const afterAgainSignal = await readFile(signalPath, "utf8");
      assert.equal(afterAgainBase, afterBase);
      assert.equal(afterAgainSignal, afterSignal);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
