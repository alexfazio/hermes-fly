export interface StatusDetails {
  appName: string;
  status: string | null;
  machine: string | null;
  region: string | null;
  hostname: string | null;
}

export type StatusReadResult =
  | { kind: "ok"; details: StatusDetails }
  | { kind: "error"; message: string };

export interface StatusReaderPort {
  getStatus(appName: string): Promise<StatusReadResult>;
}
