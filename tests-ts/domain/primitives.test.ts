import assert from "node:assert/strict";
import test from "node:test";

import { DeploymentIntent } from "../../src/contexts/deploy/domain/deployment-intent";
import { DeploymentPlan } from "../../src/contexts/deploy/domain/deployment-plan";
import { ProvenanceRecord } from "../../src/contexts/deploy/domain/provenance-record";
import { DriftFinding } from "../../src/contexts/diagnostics/domain/drift-finding";
import { MessagingPolicy } from "../../src/contexts/messaging/domain/messaging-policy";
import { ReleaseContract } from "../../src/contexts/release/domain/release-contract";

const expectError = (fn: () => void, expectedMessage: string): void => {
  assert.throws(fn, (error: unknown) => {
    assert.ok(error instanceof Error);
    assert.equal(error.message, expectedMessage);
    return true;
  });
};

test("DeploymentIntent accepts valid input and trims/defaults fields", () => {
  const intent = DeploymentIntent.create({
    appName: "  app  ",
    region: "  iad  ",
    vmSize: "  shared-cpu-1x  ",
    provider: "  openrouter  ",
    model: "  hermes  ",
  });

  assert.equal(intent.appName, "app");
  assert.equal(intent.region, "iad");
  assert.equal(intent.vmSize, "shared-cpu-1x");
  assert.equal(intent.provider, "openrouter");
  assert.equal(intent.model, "hermes");
  assert.equal(intent.channel, "stable");
});

test("DeploymentIntent rejects invalid channel and empty required fields", () => {
  expectError(
    () =>
      DeploymentIntent.create({
        appName: "app",
        region: "iad",
        vmSize: "shared-cpu-1x",
        provider: "openrouter",
        model: "hermes",
        channel: "bad" as never,
      }),
    "DeploymentIntent.channel must be one of stable|preview|edge",
  );

  expectError(
    () =>
      DeploymentIntent.create({
        appName: "   ",
        region: "iad",
        vmSize: "shared-cpu-1x",
        provider: "openrouter",
        model: "hermes",
      }),
    "DeploymentIntent.appName must be non-empty",
  );
});

test("DeploymentPlan enforces stable pin, compat version, and strict ISO timestamp", () => {
  const stableIntent = DeploymentIntent.create({
    appName: "app",
    region: "iad",
    vmSize: "shared-cpu-1x",
    provider: "openrouter",
    model: "hermes",
    channel: "stable",
  });

  const previewIntent = DeploymentIntent.create({
    appName: "app",
    region: "iad",
    vmSize: "shared-cpu-1x",
    provider: "openrouter",
    model: "hermes",
    channel: "preview",
  });

  const validPlan = DeploymentPlan.create({
    intent: previewIntent,
    hermesAgentRef: "refs/tags/v1.2.3",
    compatPolicyVersion: "v1.2.3",
    createdAtIso: "2026-03-12T12:34:56.000Z",
  });
  assert.equal(validPlan.createdAtIso, "2026-03-12T12:34:56.000Z");

  expectError(
    () =>
      DeploymentPlan.create({
        intent: stableIntent,
        hermesAgentRef: "main",
        compatPolicyVersion: "v1.2.3",
        createdAtIso: "2026-03-12T12:34:56.000Z",
      }),
    "DeploymentPlan.hermesAgentRef must be pinned for stable channel",
  );

  expectError(
    () =>
      DeploymentPlan.create({
        intent: stableIntent,
        hermesAgentRef: "refs/tags/v1.2.3",
        compatPolicyVersion: "1.2.3",
        createdAtIso: "2026-03-12T12:34:56.000Z",
      }),
    "DeploymentPlan.compatPolicyVersion must be semver with v prefix",
  );

  expectError(
    () =>
      DeploymentPlan.create({
        intent: previewIntent,
        hermesAgentRef: "refs/tags/v1.2.3",
        compatPolicyVersion: "v1.2.3",
        createdAtIso: "March 12, 2026",
      }),
    "DeploymentPlan.createdAtIso must be valid ISO-8601",
  );

  expectError(
    () =>
      DeploymentPlan.create({
        intent: previewIntent,
        hermesAgentRef: "refs/tags/v1.2.3",
        compatPolicyVersion: "v1.2.3",
        createdAtIso: "2026-03-12T12:34:56Z",
      }),
    "DeploymentPlan.createdAtIso must be valid ISO-8601",
  );
});

test("ProvenanceRecord validates channel and required fields", () => {
  expectError(
    () =>
      ProvenanceRecord.create({
        hermesFlyVersion: "1.0.0",
        hermesAgentRef: "refs/tags/v1.0.0",
        compatPolicyVersion: "v1.0.0",
        reasoningEffort: "high",
        llmProvider: "openrouter",
        llmModel: "hermes",
        deployChannel: "nope" as never,
        writtenAt: "2026-03-12T12:34:56.000Z",
      }),
    "ProvenanceRecord.deployChannel must be one of stable|preview|edge",
  );

  expectError(
    () =>
      ProvenanceRecord.create({
        hermesFlyVersion: "",
        hermesAgentRef: "refs/tags/v1.0.0",
        compatPolicyVersion: "v1.0.0",
        reasoningEffort: "high",
        llmProvider: "openrouter",
        llmModel: "hermes",
        deployChannel: "stable",
        writtenAt: "2026-03-12T12:34:56.000Z",
      }),
    "ProvenanceRecord.hermesFlyVersion must be non-empty",
  );
});

test("DriftFinding validates severity and kind", () => {
  expectError(
    () =>
      DriftFinding.create({
        code: "D001",
        message: "oops",
        subject: "release",
        severity: "fatal" as never,
        kind: "missing",
      }),
    "DriftFinding.severity must be info|warn|error",
  );

  expectError(
    () =>
      DriftFinding.create({
        code: "D001",
        message: "oops",
        subject: "release",
        severity: "warn",
        kind: "other" as never,
      }),
    "DriftFinding.kind must be missing|mismatch|unexpected",
  );
});

test("MessagingPolicy enforces mode and user-id invariants", () => {
  const onlyMe = MessagingPolicy.create("only_me", [123]);
  assert.equal(onlyMe.mode, "only_me");
  assert.deepEqual(onlyMe.allowedUsers, [123]);

  const specific = MessagingPolicy.create("specific_users", [1, 2, 3]);
  assert.equal(specific.mode, "specific_users");
  assert.deepEqual(specific.allowedUsers, [1, 2, 3]);

  const anyone = MessagingPolicy.create("anyone", []);
  assert.equal(anyone.mode, "anyone");
  assert.deepEqual(anyone.allowedUsers, []);

  expectError(
    () => MessagingPolicy.create("invalid" as never, []),
    "MessagingPolicy.mode must be only_me|specific_users|anyone",
  );
  expectError(
    () => MessagingPolicy.create("only_me", []),
    "MessagingPolicy.only_me requires exactly one numeric user id",
  );
  expectError(
    () => MessagingPolicy.create("specific_users", []),
    "MessagingPolicy.specific_users requires one or more numeric user ids",
  );
  expectError(
    () => MessagingPolicy.create("specific_users", [1, 1]),
    "MessagingPolicy.specific_users requires one or more numeric user ids",
  );
  expectError(
    () => MessagingPolicy.create("anyone", [42]),
    "MessagingPolicy.anyone must not include user ids",
  );
});

test("ReleaseContract enforces semver invariants and tag/version match", () => {
  const contract = ReleaseContract.create({
    tag: "v1.2.3",
    hermesFlyVersion: "1.2.3",
  });
  assert.equal(contract.tag, "v1.2.3");
  assert.equal(contract.hermesFlyVersion, "1.2.3");

  expectError(
    () =>
      ReleaseContract.create({
        tag: "1.2.3",
        hermesFlyVersion: "1.2.3",
      }),
    "ReleaseContract.tag must be semver with v prefix",
  );

  expectError(
    () =>
      ReleaseContract.create({
        tag: "v1.2.3",
        hermesFlyVersion: "v1.2.3",
      }),
    "ReleaseContract.hermesFlyVersion must be semver",
  );

  expectError(
    () =>
      ReleaseContract.create({
        tag: "v1.2.4",
        hermesFlyVersion: "1.2.3",
      }),
    "ReleaseContract.tag must match hermesFlyVersion",
  );
});
