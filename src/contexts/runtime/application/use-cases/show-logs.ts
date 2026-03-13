import type { LogsReadResult, LogsReaderPort } from "../ports/logs-reader.port.js";

export class ShowLogsUseCase {
  constructor(private readonly reader: LogsReaderPort) {}

  async execute(appName: string): Promise<LogsReadResult> {
    return this.reader.getLogs(appName);
  }
}
