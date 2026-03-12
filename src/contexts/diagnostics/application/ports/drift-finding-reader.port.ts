import type { DriftFinding } from "../../domain/drift-finding.js";

export interface DriftFindingReaderPort {
  readAll(): Promise<DriftFinding[]>;
}
