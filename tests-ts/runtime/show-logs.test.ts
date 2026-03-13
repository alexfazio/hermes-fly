import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, it } from "node:test";
import { tmpdir } from "node:os";

import { FlyctlAdapter } from "../../src/adapters/flyctl.ts";
import type { ProcessRunner } from "../../src/adapters/process.ts";
import type { LogsReaderPort } from "../../src/contexts/runtime/application/ports/logs-reader.port.ts";
import { ShowLogsUseCase } from "../../src/contexts/runtime/application/use-cases/show-logs.ts";
import { FlyLogsReader } from "../../src/contexts/runtime/infrastructure/adapters/fly-logs-reader.ts";
import { runLogsCommand } from "../../src/commands/logs.ts";

// ---------------------------------------------------------------
// ShowLogsUseCase
// ---------------------------------------------------------------

describe("ShowLogsUseCase", () => {
  it("success path returns raw stdout, stderr, and exit 0", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "log line 1\nlog line 2\n", stderr: "", exitCode: 0 }),
      streamLogs: async () => ({ exitCode: 0 })
    };

    const useCase = new ShowLogsUseCase(reader);
    const result = await useCase.execute("test-app");

    assert.equal(result.stdout, "log line 1\nlog line 2\n");
    assert.equal(result.stderr, "");
    assert.equal(result.exitCode, 0);
  });

  it("failure path preserves non-zero exit code", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "", stderr: "Error: app not found\n", exitCode: 1 }),
      streamLogs: async () => ({ exitCode: 1 })
    };

    const useCase = new ShowLogsUseCase(reader);
    const result = await useCase.execute("bad-app");

    assert.equal(result.exitCode, 1);
    assert.equal(result.stderr, "Error: app not found\n");
  });
});

// ---------------------------------------------------------------
// FlyLogsReader
// ---------------------------------------------------------------

describe("FlyLogsReader", () => {
  it("passes through raw result from flyctl", async () => {
    const runner: ProcessRunner = {
      run: async () => ({
        stdout: "2024-01-15T10:00:00Z [info] Hermes gateway started\n",
        stderr: "",
        exitCode: 0
      })
    };

    const adapter = new FlyctlAdapter(runner);
    const reader = new FlyLogsReader(adapter);
    const result = await reader.getLogs("test-app");

    assert.equal(result.stdout, "2024-01-15T10:00:00Z [info] Hermes gateway started\n");
    assert.equal(result.stderr, "");
    assert.equal(result.exitCode, 0);
  });
});

// ---------------------------------------------------------------
// runLogsCommand
// ---------------------------------------------------------------

describe("runLogsCommand", () => {
  it("writes raw stdout and stderr passthrough and returns 0 on success", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "log line 1\nlog line 2\n", stderr: "some warning\n", exitCode: 0 }),
      streamLogs: async (_app, opts) => {
        opts?.onStdoutChunk?.("log line 1\nlog line 2\n");
        opts?.onStderrChunk?.("some warning\n");
        return { exitCode: 0 };
      }
    };

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "test-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "log line 1\nlog line 2\n");
    // non-empty stderr passthrough on success
    assert.equal(errChunks.join(""), "some warning\n");
  });

  it("writes failure contract line to stderr and returns 1 on exitCode=1", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "", stderr: "Error: app not found\n", exitCode: 1 }),
      streamLogs: async () => ({ exitCode: 1 })
    };

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "bad-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 1);
    assert.equal(outChunks.join(""), "");
    assert.equal(errChunks.join(""), "[error] Failed to fetch logs for app 'bad-app'\n");
  });

  it("writes no-app error to stderr and returns 1 when no app resolved", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-logs-noapp-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const errChunks: string[] = [];
      const outChunks: string[] = [];
      const stderr = { write: (s: string) => { errChunks.push(s); } };
      const stdout = { write: (s: string) => { outChunks.push(s); } };

      const reader: LogsReaderPort = {
        getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
        streamLogs: async () => ({ exitCode: 0 })
      };

      const code = await runLogsCommand([], {
        useCase: new ShowLogsUseCase(reader),
        stderr,
        stdout,
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });

      assert.equal(code, 1);
      assert.equal(outChunks.join(""), "");
      assert.equal(errChunks.join(""), "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("ignores unknown args and only uses -a APP", async () => {
    const reader: LogsReaderPort = {
      getLogs: async (app: string) => ({ stdout: `logs for ${app}\n`, stderr: "", exitCode: 0 }),
      streamLogs: async (app, opts) => {
        opts?.onStdoutChunk?.(`logs for ${app}\n`);
        return { exitCode: 0 };
      }
    };

    const outChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: () => {} };

    const code = await runLogsCommand(["--unknown-flag", "-a", "my-app", "--json"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "logs for my-app\n");
  });

  it("-a without value falls back to current app", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-logs-fallback-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      await writeFile(
        join(root, "config", "config.yaml"),
        "current_app: fallback-app\n",
        "utf8"
      );

      const reader: LogsReaderPort = {
        getLogs: async (app: string) => ({ stdout: `logs for ${app}\n`, stderr: "", exitCode: 0 }),
        streamLogs: async (app, opts) => {
          opts?.onStdoutChunk?.(`logs for ${app}\n`);
          return { exitCode: 0 };
        }
      };

      const outChunks: string[] = [];
      const stdout = { write: (s: string) => { outChunks.push(s); } };
      const stderr = { write: () => {} };

      const code = await runLogsCommand(["-a"], {
        useCase: new ShowLogsUseCase(reader),
        stdout,
        stderr,
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });

      assert.equal(code, 0);
      assert.equal(outChunks.join(""), "logs for fallback-app\n");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  it("repeated -a uses last value", async () => {
    const reader: LogsReaderPort = {
      getLogs: async (app: string) => ({ stdout: `logs for ${app}\n`, stderr: "", exitCode: 0 }),
      streamLogs: async (app, opts) => {
        opts?.onStdoutChunk?.(`logs for ${app}\n`);
        return { exitCode: 0 };
      }
    };

    const outChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: () => {} };

    const code = await runLogsCommand(["-a", "first", "-a", "last-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "logs for last-app\n");
  });

  it("success with non-empty stderr passes through when exitCode is 0", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "log output\n", stderr: "warning line\n", exitCode: 0 }),
      streamLogs: async (_app, opts) => {
        opts?.onStdoutChunk?.("log output\n");
        opts?.onStderrChunk?.("warning line\n");
        return { exitCode: 0 };
      }
    };

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "test-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "log output\n");
    assert.equal(errChunks.join(""), "warning line\n");
  });

  it("failure case with exitCode=1 and non-empty stderr prints failure line only", async () => {
    const reader: LogsReaderPort = {
      getLogs: async () => ({ stdout: "", stderr: "some fly error\n", exitCode: 1 }),
      streamLogs: async (_app, opts) => {
        opts?.onStderrChunk?.("some fly error\n");
        return { exitCode: 1 };
      }
    };

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "bad-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 1);
    assert.equal(outChunks.join(""), "");
    assert.equal(errChunks.join(""), "[error] Failed to fetch logs for app 'bad-app'\n");
  });
});

// ---------------------------------------------------------------
// runLogsCommand resolve-app edge cases (Slice B: PR-D2 Review-2)
// ---------------------------------------------------------------

describe("runLogsCommand resolve-app edge cases", () => {
  it("runLogsCommand with trailing -a after valid value uses no-app error when no fallback", async () => {
    const root = await mkdtemp(join(tmpdir(), "hermes-logs-trail-a-"));
    try {
      await mkdir(join(root, "config"), { recursive: true });
      const errChunks: string[] = [];
      const outChunks: string[] = [];
      const stderr = { write: (s: string) => { errChunks.push(s); } };
      const stdout = { write: (s: string) => { outChunks.push(s); } };

      const reader: LogsReaderPort = {
        getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
        streamLogs: async () => ({ exitCode: 0 })
      };

      const code = await runLogsCommand(["-a", "first", "-a"], {
        useCase: new ShowLogsUseCase(reader),
        stderr,
        stdout,
        env: { ...process.env, HERMES_FLY_CONFIG_DIR: join(root, "config") }
      });

      assert.equal(code, 1);
      assert.equal(outChunks.join(""), "");
      assert.equal(errChunks.join(""), "[error] No app specified. Use -a APP or run 'hermes-fly deploy' first.\n");
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});

// ---------------------------------------------------------------
// runLogsCommand streaming path (Slice A: PR-D2 Review-2)
// ---------------------------------------------------------------

describe("runLogsCommand streaming path", () => {
  it("spawn/runner rejection in logs path -> exit 1, stderr exactly contract failure", async () => {
    const reader = {
      getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      streamLogs: async (_appName: string, _opts?: unknown) => {
        throw new Error("spawn ENOENT");
      }
    } as unknown as LogsReaderPort;

    const errChunks: string[] = [];
    const outChunks: string[] = [];
    const stderr = { write: (s: string) => { errChunks.push(s); } };
    const stdout = { write: (s: string) => { outChunks.push(s); } };

    const code = await runLogsCommand(["-a", "bad-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 1);
    assert.equal(outChunks.join(""), "");
    assert.equal(errChunks.join(""), "[error] Failed to fetch logs for app 'bad-app'\n");
  });

  it("callbacks receive chunks in order; output sink receives chunk order unchanged", async () => {
    const reader = {
      getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      streamLogs: async (_appName: string, opts?: { onStdoutChunk?: (s: string) => void }) => {
        opts?.onStdoutChunk?.("chunk-1");
        opts?.onStdoutChunk?.("chunk-2");
        opts?.onStdoutChunk?.("chunk-3");
        return { exitCode: 0 };
      }
    } as unknown as LogsReaderPort;

    const outChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: () => {} };

    const code = await runLogsCommand(["-a", "test-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.deepEqual(outChunks, ["chunk-1", "chunk-2", "chunk-3"]);
  });

  it("success path with non-empty stderr still passes through on exitCode=0", async () => {
    const reader = {
      getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      streamLogs: async (_appName: string, opts?: { onStdoutChunk?: (s: string) => void; onStderrChunk?: (s: string) => void }) => {
        opts?.onStdoutChunk?.("log output\n");
        opts?.onStderrChunk?.("warning line\n");
        return { exitCode: 0 };
      }
    } as unknown as LogsReaderPort;

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "test-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 0);
    assert.equal(outChunks.join(""), "log output\n");
    assert.equal(errChunks.join(""), "warning line\n");
  });

  it("non-zero exit after stdout chunks: stdout contains chunks, buffered stderr omitted, contract failure line emitted", async () => {
    const reader = {
      getLogs: async () => ({ stdout: "", stderr: "", exitCode: 0 }),
      streamLogs: async (_appName: string, opts?: { onStdoutChunk?: (s: string) => void; onStderrChunk?: (s: string) => void }) => {
        opts?.onStdoutChunk?.("log chunk before failure\n");
        opts?.onStderrChunk?.("raw fly error output\n");
        return { exitCode: 1 };
      }
    } as unknown as LogsReaderPort;

    const outChunks: string[] = [];
    const errChunks: string[] = [];
    const stdout = { write: (s: string) => { outChunks.push(s); } };
    const stderr = { write: (s: string) => { errChunks.push(s); } };

    const code = await runLogsCommand(["-a", "bad-app"], {
      useCase: new ShowLogsUseCase(reader),
      stdout,
      stderr
    });

    assert.equal(code, 1);
    assert.equal(outChunks.join(""), "log chunk before failure\n");
    assert.ok(!errChunks.join("").includes("raw fly error output"), "buffered stderr should not appear on non-zero exit");
    assert.equal(errChunks.join(""), "[error] Failed to fetch logs for app 'bad-app'\n");
  });
});
