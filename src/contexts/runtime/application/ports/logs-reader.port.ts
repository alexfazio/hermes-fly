export interface LogsReadResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface LogsReaderPort {
  getLogs(appName: string): Promise<LogsReadResult>;
}
