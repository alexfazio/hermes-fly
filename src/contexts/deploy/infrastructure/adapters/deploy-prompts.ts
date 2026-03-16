import { createInterface } from "node:readline/promises";

export interface DeployPromptPort {
  isInteractive(): boolean;
  write(message: string): void;
  ask(message: string): Promise<string>;
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

  async pause(message: string): Promise<void> {
    await this.ask(message);
  }
}
