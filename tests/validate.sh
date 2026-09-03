#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
    printf 'codpiece validate: %s\n' "$*" >&2
    exit 1
}

for file in \
    AGENTS.md CONTEXT.md LICENSE MAINTAIN.md README.md SCRATCHPAD.md \
    gate/budgets.json gate/first-party-allowlist.txt; do
    [ -f "$file" ] || fail "$file is missing"
done

scripts=(
    scripts/bootstrap-branches.sh
    scripts/build-lock.sh
    scripts/gate-contract.sh
    scripts/gate.sh
    scripts/install.sh
    scripts/reconcile-branches.sh
    tests/bootstrap-branches.sh
    tests/install-transaction.sh
    tests/validate.sh
)
for script in "${scripts[@]}"; do
    bash -n "$script"
    [ -x "$script" ] || fail "$script is not executable"
done

[ "$(readlink CLAUDE.md)" = AGENTS.md ] \
    || fail "CLAUDE.md must link to AGENTS.md"

for section in Purpose Upstream 'Branch model' Features Gate Consumer Notify; do
    grep -Fx "## $section" MAINTAIN.md >/dev/null \
        || fail "MAINTAIN.md is missing section: ## $section"
done
if grep -F agentwiki MAINTAIN.md >/dev/null; then
    fail "MAINTAIN.md must be self-contained"
fi

grep -F 'paired commits' AGENTS.md >/dev/null \
    || fail "AGENTS.md does not require paired product and inventory commits"
grep -F 'The user does not need' AGENTS.md >/dev/null \
    || fail "AGENTS.md does not classify ordinary feature requests"

features=$(awk '
    /^## Features$/ { inside = 1; next }
    /^## / && inside { exit }
    inside { print }
' MAINTAIN.md)
mapped=$(printf '%s\n' "$features" \
    | sed -n 's/^| \(carry\/[a-z0-9-]*\) |.*$/\1/p')
expected_carries=$(printf '%s\n' 'carry/voice-sidecar' 'carry/fx-authorization')
[ "$mapped" = "$expected_carries" ] \
    || fail "active inventory must be carry/voice-sidecar then carry/fx-authorization"

for planned_contract in \
    'carry/fx-authorization' \
    'carry/codex-credential-authority' \
    'VoiceAuthority-to-RuntimeLease' \
    'codex.credential.refresh' \
    'retry exactly once' \
    'passes only that inherited' \
    'bearer token and remains replayable' \
    'do not traverse'; do
    grep -F "$planned_contract" MAINTAIN.md >/dev/null \
        || fail "planned single-authority contract is missing: $planned_contract"
done
if grep -F 'replayed outside its bound process/session' MAINTAIN.md >/dev/null; then
    fail "authorization contract claims unavailable bearer-token binding"
fi

for product_contract in \
    'zero Codex work turns' \
    'No hosted CI proof is required' \
    'scripts/bootstrap-branches.sh --apply' \
    'bun run check' \
    'bun run tui' \
    'Title: Codpiece Maintenance'; do
    grep -F "$product_contract" MAINTAIN.md >/dev/null \
        || fail "product contract is missing: $product_contract"
done

for declared in \
    'MAINTAIN_FORK_REPO=possibilities/codex' \
    'MAINTAIN_UPSTREAM_REPO=openai/codex' \
    'MAINTAIN_MAIN_BRANCH=main' \
    'MAINTAIN_INTEGRATION_BRANCH=integration' \
    'MAINTAIN_CARRY_PREFIX=carry/' \
    'MAINTAIN_QUARANTINE_PREFIX=DELETEME/' \
    'MAINTAIN_PRESERVE_OPEN_PRS=0'; do
    grep -F "export $declared" scripts/reconcile-branches.sh >/dev/null \
        || fail "branch adapter does not declare $declared"
done
grep -F 'carry/fx-authorization' scripts/reconcile-branches.sh >/dev/null \
    || fail "branch adapter does not enforce the exact active carry"
if grep -E 'git .*(push|fetch|update-ref)' scripts/reconcile-branches.sh >/dev/null; then
    fail "normal branch adapter contains namespace mechanics"
fi

set +e
missing_output=$(MAINTAIN_SKILL_DIR=/nonexistent \
    scripts/reconcile-branches.sh --check 2>&1)
missing_status=$?
set -e
[ "$missing_status" -ne 0 ] \
    || fail "branch adapter ran without the maintain skill"
printf '%s\n' "$missing_output" \
    | grep -F 'the maintain skill is not installed' >/dev/null \
    || fail "missing maintain skill is not explained"

for bootstrap_contract in \
    'push --quiet --atomic' \
    "--force-with-lease=\"refs/heads/main:\$fork_main_sha\"" \
    '--force-with-lease=refs/heads/integration:' \
    "--force-with-lease=\"refs/heads/\$voice_branch:\"" \
    'bootstrap_state=repair-local' \
    'local-build receipt does not prove'; do
    grep -F -- "$bootstrap_contract" scripts/bootstrap-branches.sh >/dev/null \
        || fail "bootstrap omits: $bootstrap_contract"
done

plan=$(scripts/install.sh --check)
for required in \
    'source: fork/integration' \
    'exact full SHA only' \
    'current-contract local-build receipt' \
    'detached codex-voice-sidecar' \
    'two Cargo jobs' \
    'release LTO off' \
    'symbols stripped' \
    'SHA-isolated directories' \
    'atomic consumer pointer' \
    'installed receipt'; do
    printf '%s\n' "$plan" | grep -F "$required" >/dev/null \
        || fail "installer plan is missing: $required"
done
grep -F 'worktree add --quiet --detach' scripts/install.sh >/dev/null \
    || fail "installer does not build from a detached worktree"
grep -F "fork/integration is \$published, not requested \$expected_sha" \
    scripts/install.sh >/dev/null \
    || fail "installer does not bind the exact published SHA"
grep -F "local-builds/\$expected_sha.json" scripts/install.sh >/dev/null \
    || fail "installer does not consume the exact local-build receipt"
grep -F "local-builds/\$expected_sha.json" scripts/install.sh >/dev/null \
    || fail "installer does not consume the exact local-build receipt"
grep -F 'rollback_current' scripts/install.sh >/dev/null \
    || fail "installer has no consumer-pointer rollback"
grep -F "buildReceiptSha256:\$buildReceiptSha256" scripts/install.sh >/dev/null \
    || fail "installer receipt does not bind the build receipt by hash"
grep -F "metadataSha256:\$metadataSha256" scripts/install.sh >/dev/null \
    || fail "installer receipt does not bind metadata by hash"
if grep -E 'git .*(rebase|push)' scripts/install.sh >/dev/null; then
    fail "installer contains maintenance behavior"
fi

for script in scripts/gate.sh scripts/install.sh; do
    grep -F 'CARGO_BUILD_JOBS=2' "$script" >/dev/null \
        || fail "$script does not cap Cargo jobs"
    grep -F 'CARGO_PROFILE_RELEASE_LTO=false' "$script" >/dev/null \
        || fail "$script does not disable release LTO"
    grep -F 'CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1' "$script" >/dev/null \
        || fail "$script does not serialize release codegen"
    grep -F 'CARGO_PROFILE_RELEASE_STRIP=symbols' "$script" >/dev/null \
        || fail "$script does not strip packaged release symbols"
done
for gate in scripts/gate.sh scripts/install.sh; do
    grep -F 'codpiece_release_lock_' "$gate" >/dev/null \
        || fail "$gate does not participate in the release lock"
done
for test_remote_guard in scripts/bootstrap-branches.sh \
    scripts/install.sh scripts/reconcile-branches.sh; do
    grep -F 'codpiece_require_local_test_remote' "$test_remote_guard" >/dev/null \
        || fail "$test_remote_guard does not reject non-local test remotes"
done
grep -F 'CODPIECE_CANONICAL_FORK_URL=https://github.com/possibilities/codex.git' \
    scripts/gate-contract.sh >/dev/null \
    || fail "gate contract does not hardcode the canonical fork identity"
grep -F 'CODPIECE_CANONICAL_UPSTREAM_URL=https://github.com/openai/codex.git' \
    scripts/gate-contract.sh >/dev/null \
    || fail "gate contract does not hardcode the canonical upstream identity"
grep -F "codpiece_release_lock_acquire \"\$state_root\"" \
    scripts/bootstrap-branches.sh >/dev/null \
    || fail "bootstrap does not hold the shared release lock around receipts"
grep -F "target_dir=\"\$target_base/reproductions/\$expected_sha\"" \
    scripts/install.sh >/dev/null \
    || fail "installer does not use a distinct reproduction target"
grep -F "install -m 0600 \"\$metadata_source\" \"\$staging/metadata.json\"" \
    scripts/install.sh >/dev/null \
    || fail "installer does not copy exact local-build metadata"
grep -F '.credentialAuthority.descriptor == 3' scripts/install.sh >/dev/null \
    || fail "installer does not verify the schema-3 credential authority"
grep -F 'schemaVersion:3' scripts/gate.sh >/dev/null \
    || fail "gate does not emit schema-3 sidecar metadata"

for forbidden in \
    codex-app-server codex-core codex-protocol codex-mcp-server codex-tools \
    codex-rollout codex-state codex-thread-store codex-sandboxing \
    codex-linux-sandbox codex-rmcp-client; do
    grep -F "$forbidden" scripts/gate.sh >/dev/null \
        || fail "gate does not reject forbidden dependency $forbidden"
done
grep -F "just test -p \"\$package\"" scripts/gate.sh >/dev/null \
    || fail "gate bypasses the upstream targeted-test command"
grep -F "just fix -p \"\$package\"" scripts/gate.sh >/dev/null \
    || fail "gate bypasses the upstream targeted-fix command"
grep -F 'just fmt' scripts/gate.sh >/dev/null \
    || fail "gate bypasses upstream formatting"
grep -F -- "--format '{p}'" scripts/gate.sh >/dev/null \
    || fail "gate does not render stable Cargo package identities"
grep -F "sed 's/ (\\*)\$//; /^[[:space:]]*\$/d'" scripts/gate.sh >/dev/null \
    || fail "gate counts Cargo packages without canonicalizing duplicate markers"
if grep -E 'cargo test' scripts/gate.sh >/dev/null; then
    fail "gate invokes cargo test directly"
fi
jq -e '
    .schemaVersion == 1 and
    ((.binaryBytesMax == null and .dependencyCountMax == null and
      .status == "awaiting-first-slim-build") or
     ((.binaryBytesMax | type == "number") and .binaryBytesMax > 0 and
      (.dependencyCountMax | type == "number") and .dependencyCountMax > 0 and
      .status == "enforced"))
' gate/budgets.json >/dev/null || fail "size/dependency budgets are invalid"

checkout="${CODPIECE_CODEX_CHECKOUT:-$HOME/src/codex}"
if git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local_carries=$(git -C "$checkout" for-each-ref \
        --format='%(refname:short)' refs/heads/carry/ | LC_ALL=C sort)
    expected_local=$(printf '%s\n' 'carry/fx-authorization' 'carry/voice-sidecar')
    [ "$local_carries" = "$expected_local" ] \
        || fail "bound checkout has a carry outside the active inventory"
    if git -C "$checkout" show-ref --verify --quiet refs/heads/integration; then
        [ "$(git -C "$checkout" rev-parse refs/heads/integration)" = \
            "$(git -C "$checkout" rev-parse refs/heads/carry/fx-authorization)" ] \
            || fail "Integration does not exactly equal the top carry"
    fi
fi

tests/bootstrap-branches.sh
tests/install-transaction.sh

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${scripts[@]}"
fi

if jq -e '.status == "awaiting-first-slim-build"' gate/budgets.json >/dev/null; then
    printf 'codpiece Workshop scaffold validation passed; product budgets are not established.\n'
else
    printf 'codpiece Workshop validation passed.\n'
fi
