import type { StatusReaderPort, StatusReadResult } from "../ports/status-reader.port.js";

export class ShowStatusUseCase {
  constructor(private readonly reader: StatusReaderPort) {}

  async execute(appName: string): Promise<StatusReadResult> {
    return this.reader.getStatus(appName);
  }
}
