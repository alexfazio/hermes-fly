#!/usr/bin/env bash
set -euo pipefail

test -f src/contexts/deploy/domain/deployment-intent.ts
test -f src/contexts/deploy/domain/deployment-plan.ts
test -f src/contexts/deploy/domain/provenance-record.ts
test -f src/contexts/diagnostics/domain/drift-finding.ts
test -f src/contexts/messaging/domain/messaging-policy.ts
test -f src/contexts/release/domain/release-contract.ts
test -f src/contexts/deploy/application/ports/deployment-plan-writer.port.ts
test -f src/contexts/diagnostics/application/ports/drift-finding-reader.port.ts
test -f src/contexts/messaging/application/ports/messaging-policy-repository.port.ts
test -f src/contexts/release/application/ports/release-contract-checker.port.ts
test -f src/contexts/runtime/application/ports/legacy-command-runner.port.ts
test -f src/legacy/bash-bridge-contract.ts
test -f tests-ts/domain/primitives.test.ts
test -f scripts/verify-pr-b1-domain-primitives.sh

npm run typecheck
npm run arch:ddd-boundaries
npm run test:domain-primitives

tests/bats/bin/bats tests/hybrid-dispatch.bats tests/integration.bats

echo "PR-B1 verification passed."
