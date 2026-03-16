import { spawn } from "node:child_process";

export interface ProcessResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface ProcessRunOptions {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  onStdoutChunk?: (chunk: string) => void;
  onStderrChunk?: (chunk: string) => void;
}

export interface ProcessRunner {
  run(command: string, args: string[], options?: ProcessRunOptions): Promise<ProcessResult>;
  runStreaming(command: string, args: string[], options?: ProcessRunOptions): Promise<{ exitCode: number }>;
}

export interface ForegroundProcessRunner extends ProcessRunner {
  runForeground(command: string, args: string[], options?: ProcessRunOptions): Promise<{ exitCode: number }>;
}

export class NodeProcessRunner implements ForegroundProcessRunner {
  async run(command: string, args: string[], options: ProcessRunOptions = {}): Promise<ProcessResult> {
    return await new Promise<ProcessResult>((resolve, reject) => {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: {
          ...process.env,
          ...options.env
        },
        stdio: ["ignore", "pipe", "pipe"]
      });

      let stdout = "";
      let stderr = "";

      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk: string) => {
        stdout += chunk;
      });

      child.stderr.setEncoding("utf8");
      child.stderr.on("data", (chunk: string) => {
        stderr += chunk;
      });

      child.on("error", reject);
      child.on("close", (code) => {
        resolve({
          stdout,
          stderr,
          exitCode: typeof code === "number" ? code : 1
        });
      });
    });
  }

  async runStreaming(command: string, args: string[], options: ProcessRunOptions = {}): Promise<{ exitCode: number }> {
    return new Promise<{ exitCode: number }>((resolve, reject) => {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: {
          ...process.env,
          ...options.env
        },
        stdio: ["ignore", "pipe", "pipe"]
      });

      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk: string) => {
        options.onStdoutChunk?.(chunk);
      });

      child.stderr.setEncoding("utf8");
      child.stderr.on("data", (chunk: string) => {
        options.onStderrChunk?.(chunk);
      });

      child.on("error", reject);
      child.on("close", (code) => {
        resolve({ exitCode: typeof code === "number" ? code : 1 });
      });
    });
  }

  async runForeground(command: string, args: string[], options: ProcessRunOptions = {}): Promise<{ exitCode: number }> {
    return new Promise<{ exitCode: number }>((resolve, reject) => {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: {
          ...process.env,
          ...options.env
        },
        stdio: "inherit"
      });

      child.on("error", reject);
      child.on("close", (code) => {
        resolve({ exitCode: typeof code === "number" ? code : 1 });
      });
    });
  }
}
