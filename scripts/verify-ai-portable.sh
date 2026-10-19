#!/usr/bin/env bash
# Offline portable verification. No provider key or iPhone required.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/swift.sh packages/DryRunCore test
scripts/swift.sh packages/DryRunVault test -j 4
pnpm --dir services/public-api test
pnpm --dir services/ai-orchestrator typecheck
pnpm --dir services/ai-orchestrator test
pnpm --dir services/ai-orchestrator eval
for check in preparation-inventory-eval inventory-validation-eval source-assessment-eval assessment-policy-eval contracts fallback-resume-eval fallback-resume-replay replay-eval spatial-policy-replay inventory-session-eval food-session-eval food-session-replay concern-eval resource-refresh-eval practice-capture-eval practice-adaptation-eval helper-eval stress-eval score-stability startup-eval; do
    pnpm --dir services/ai-orchestrator exec tsx "scripts/$check.ts"
done
DRYRUN_PIPELINE_OUTPUT=../../fixtures/ai/integrated-pipeline-policy.json pnpm --dir services/ai-orchestrator exec tsx scripts/pipeline-replay.ts
