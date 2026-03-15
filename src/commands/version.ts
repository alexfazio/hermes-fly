import { HERMES_FLY_TS_VERSION } from "../version.js";

export function runVersionCommand(stdout: { write: (s: string) => void } = process.stdout): void {
  stdout.write(`hermes-fly ${HERMES_FLY_TS_VERSION}\n`);
}
