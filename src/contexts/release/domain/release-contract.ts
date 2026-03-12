export interface ReleaseContractInput {
  tag: string;
  hermesFlyVersion: string;
}

const TAG_SEMVER = /^v[0-9]+\.[0-9]+\.[0-9]+$/;
const VERSION_SEMVER = /^[0-9]+\.[0-9]+\.[0-9]+$/;

export class ReleaseContract {
  readonly tag: string;
  readonly hermesFlyVersion: string;

  private constructor(input: ReleaseContractInput) {
    this.tag = input.tag;
    this.hermesFlyVersion = input.hermesFlyVersion;
  }

  static create(input: ReleaseContractInput): ReleaseContract {
    const tag = input.tag.trim();
    if (!TAG_SEMVER.test(tag)) {
      throw new Error("ReleaseContract.tag must be semver with v prefix");
    }

    const hermesFlyVersion = input.hermesFlyVersion.trim();
    if (!VERSION_SEMVER.test(hermesFlyVersion)) {
      throw new Error("ReleaseContract.hermesFlyVersion must be semver");
    }

    if (tag.slice(1) !== hermesFlyVersion) {
      throw new Error("ReleaseContract.tag must match hermesFlyVersion");
    }

    return new ReleaseContract({
      tag,
      hermesFlyVersion,
    });
  }
}
