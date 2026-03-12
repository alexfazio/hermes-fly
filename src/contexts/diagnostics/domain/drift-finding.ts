export type DriftSeverity = "info" | "warn" | "error";
export type DriftKind = "missing" | "mismatch" | "unexpected";

export interface DriftFindingInput {
  code: string;
  message: string;
  subject: string;
  severity: DriftSeverity;
  kind: DriftKind;
}

const SEVERITIES: readonly DriftSeverity[] = ["info", "warn", "error"];
const KINDS: readonly DriftKind[] = ["missing", "mismatch", "unexpected"];

export class DriftFinding {
  readonly code: string;
  readonly message: string;
  readonly subject: string;
  readonly severity: DriftSeverity;
  readonly kind: DriftKind;

  private constructor(input: DriftFindingInput) {
    this.code = input.code;
    this.message = input.message;
    this.subject = input.subject;
    this.severity = input.severity;
    this.kind = input.kind;
  }

  static create(input: DriftFindingInput): DriftFinding {
    const code = input.code.trim();
    if (code.length === 0) {
      throw new Error("DriftFinding.code must be non-empty");
    }

    const message = input.message.trim();
    if (message.length === 0) {
      throw new Error("DriftFinding.message must be non-empty");
    }

    const subject = input.subject.trim();
    if (subject.length === 0) {
      throw new Error("DriftFinding.subject must be non-empty");
    }

    if (!SEVERITIES.includes(input.severity)) {
      throw new Error("DriftFinding.severity must be info|warn|error");
    }

    if (!KINDS.includes(input.kind)) {
      throw new Error("DriftFinding.kind must be missing|mismatch|unexpected");
    }

    return new DriftFinding({
      code,
      message,
      subject,
      severity: input.severity,
      kind: input.kind,
    });
  }
}
