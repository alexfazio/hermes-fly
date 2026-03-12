import type { ReleaseContract } from "../../domain/release-contract.js";

export interface ReleaseContractCheckerPort {
  validate(contract: ReleaseContract): Promise<boolean>;
}
