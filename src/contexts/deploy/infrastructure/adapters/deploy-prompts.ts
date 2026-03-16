import { createInterface } from "node:readline/promises";

export interface DeployPromptPort {
  isInteractive(): boolean;
  write(message: string): void;
  ask(message: string): Promise<string>;
  askSecret(message: string): Promise<string>;
  pause(message: string): Promise<void>;
}

export class ReadlineDeployPrompts implements DeployPromptPort {
  constructor(
    private readonly input: NodeJS.ReadStream = process.stdin,
    private readonly output: NodeJS.WriteStream = process.stderr
  ) {}

  isInteractive(): boolean {
    return Boolean(this.input.isTTY && this.output.isTTY);
  }

  write(message: string): void {
    this.output.write(message);
  }

  async ask(message: string): Promise<string> {
    const rl = createInterface({
      input: this.input,
      output: this.output
    });
    try {
      const answer = await rl.question(message);
      return answer.trim();
    } finally {
      rl.close();
    }
  }

  async askSecret(message: string): Promise<string> {
    if (!this.isInteractive() || typeof this.input.setRawMode !== "function") {
      return await this.ask(message);
    }

    this.output.write(message);
    return await new Promise<string>((resolve, reject) => {
      let answer = "";
      const input = this.input;
      const wasRaw = Boolean((input as NodeJS.ReadStream & { isRaw?: boolean }).isRaw);

      const cleanup = () => {
        input.off("data", onData);
        if (!wasRaw) {
          input.setRawMode?.(false);
        }
        input.pause();
      };

      const onData = (chunk: string | Buffer) => {
        const value = typeof chunk === "string" ? chunk : chunk.toString("utf8");
        for (const char of value) {
          if (char === "\u0003") {
            cleanup();
            this.output.write("^C\n");
            reject(new Error("Aborted with Ctrl+C"));
            return;
          }

          if (char === "\r" || char === "\n") {
            cleanup();
            this.output.write("\n");
            resolve(answer.trim());
            return;
          }

          if (char === "\u007f" || char === "\b" || char === "\x08") {
            answer = answer.slice(0, -1);
            continue;
          }

          answer += char;
        }
      };

      input.setEncoding("utf8");
      if (!wasRaw) {
        input.setRawMode(true);
      }
      input.resume();
      input.on("data", onData);
    });
  }

  async pause(message: string): Promise<void> {
    await this.ask(message);
  }
}
