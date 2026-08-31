#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/build-lock.sh"
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece bootstrap: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/bootstrap-branches.sh --check|--apply\n'
}

case "${1:-}" in
    --check) mode=check ;;
    --apply) mode=apply ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
[ "$#" -eq 1 ] || {
    usage >&2
    exit 64
}

for command in git jq shasum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

checkout="${CODPIECE_CODEX_CHECKOUT:-$HOME/src/codex}"
test_mode="${CODPIECE_TESTING:-0}"
case "$test_mode" in 0|1) ;; *) die "CODPIECE_TESTING must be 0 or 1" ;; esac

git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$checkout is not a Git worktree"
[ -z "$(git -C "$checkout" status --porcelain)" ] \
    || die "$checkout has local changes"
actual_fork=$(git -C "$checkout" remote get-url fork 2>/dev/null) \
    || die "$checkout has no fork remote"
actual_origin=$(git -C "$checkout" remote get-url origin 2>/dev/null) \
    || die "$checkout has no origin remote"
if [ "$test_mode" -eq 0 ]; then
    codpiece_remote_matches "$actual_fork" "$CODPIECE_CANONICAL_FORK_URL" \
        || die "$checkout fork remote points at $actual_fork"
    codpiece_remote_matches "$actual_origin" "$CODPIECE_CANONICAL_UPSTREAM_URL" \
        || die "$checkout origin remote points at $actual_origin"
else
    codpiece_require_local_test_remote fork "$actual_fork" \
        || die "test mode remote safety check failed"
    codpiece_require_local_test_remote origin "$actual_origin" \
        || die "test mode remote safety check failed"
fi

voice_branch=carry/voice-sidecar
git -C "$checkout" rev-parse --verify --quiet "refs/heads/$voice_branch^{commit}" >/dev/null \
    || die "local $voice_branch is missing"
voice_sha=$(git -C "$checkout" rev-parse "refs/heads/$voice_branch")
codpiece_full_sha "$voice_sha" || die "$voice_branch is not a full commit SHA"
local_integration_exists=0
if git -C "$checkout" show-ref --verify --quiet refs/heads/integration; then
    local_integration_exists=1
    local_integration_sha=$(git -C "$checkout" rev-parse refs/heads/integration)
    [ "$local_integration_sha" = "$voice_sha" ] \
        || die "local integration does not equal $voice_branch"
fi

local_carries=$(git -C "$checkout" for-each-ref \
    --format='%(refname:short)' refs/heads/carry/ | LC_ALL=C sort)
[ "$local_carries" = "$voice_branch" ] \
    || die "bootstrap requires exactly one local carry: $voice_branch"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/codpiece-bootstrap.XXXXXX")
snapshot="$scratch/snapshot.git"
remote_heads="$scratch/remote-heads"
lock_dir=
release_lock_held=0
cleanup() {
    local status=$? cleanup_failed=0
    trap - EXIT
    rm -rf -- "$scratch" || cleanup_failed=1
    if [ -n "$lock_dir" ] && [ -d "$lock_dir" ]; then
        rm -f -- "$lock_dir/pid" || cleanup_failed=1
        rmdir "$lock_dir" || cleanup_failed=1
    fi
    if [ "$release_lock_held" -eq 1 ]; then
        codpiece_release_lock_release || cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'codpiece bootstrap: cleanup failed\n' >&2
        [ "$status" -ne 0 ] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT

git init --quiet --bare "$snapshot"
git --git-dir="$snapshot" fetch --quiet --no-tags "$actual_origin" \
    '+refs/heads/main:refs/bootstrap/origin/main' \
    || die "could not snapshot upstream main"
git ls-remote --heads "$actual_fork" \
    | awk -F '\t' '{ sub("^refs/heads/", "", $2); print $2 "\t" $1 }' \
    | LC_ALL=C sort >"$remote_heads" \
    || die "could not inventory fork heads"
git --git-dir="$snapshot" fetch --quiet --no-tags "$actual_fork" \
    '+refs/heads/main:refs/bootstrap/fork/main' \
    || die "could not snapshot fork main"

lookup_remote() {
    local branch=$1
    awk -F '\t' -v branch="$branch" '
        $1 == branch { print $2; found = 1; exit }
        END { if (!found) exit 1 }
    ' "$remote_heads"
}

upstream_sha=$(git --git-dir="$snapshot" rev-parse refs/bootstrap/origin/main)
fork_main_sha=$(lookup_remote main) || die "fork/main is missing"
remote_integration_sha=$(lookup_remote integration 2>/dev/null || true)
remote_voice_sha=$(lookup_remote "$voice_branch" 2>/dev/null || true)
git --git-dir="$snapshot" merge-base --is-ancestor "$fork_main_sha" "$upstream_sha" \
    || die "fork/main has commits outside upstream/main"
[ "$(git -C "$checkout" rev-parse refs/heads/main)" = "$upstream_sha" ] \
    || die "local main must exactly match upstream/main at $upstream_sha"
git -C "$checkout" merge-base --is-ancestor "$upstream_sha" "$voice_sha" \
    || die "$voice_branch does not contain upstream/main at $upstream_sha"

bootstrap_state=create
if [ -n "$remote_integration_sha" ] || [ -n "$remote_voice_sha" ]; then
    [ "$fork_main_sha" = "$upstream_sha" ] \
        && [ "$remote_integration_sha" = "$voice_sha" ] \
        && [ "$remote_voice_sha" = "$voice_sha" ] \
        || die "remote bootstrap refs already exist in a different or partial state"
    bootstrap_state=repair-local
elif [ "$local_integration_exists" -eq 1 ]; then
    die "local integration exists before the remote bootstrap"
fi

state_root="${CODPIECE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codpiece}"
codpiece_release_lock_acquire "$state_root" || die "release lock is busy"
release_lock_held=1
local_receipt="$state_root/local-builds/$voice_sha.json"
artifact_receipt="$state_root/artifact-gates/$voice_sha.json"
codpiece_regular_private_receipt "$local_receipt" \
    || die "no private regular local-build receipt for $voice_sha"
codpiece_regular_private_receipt "$artifact_receipt" \
    || die "no private regular artifact-gate receipt for $voice_sha"
contract_sha=$(codpiece_gate_contract_digest "$root") \
    || die "could not hash the gate contract"
voice_tree=$(git -C "$checkout" rev-parse "$voice_sha^{tree}")
jq -e \
    --arg sha "$voice_sha" \
    --arg tree "$voice_tree" \
    --arg contract "$contract_sha" '
        .schemaVersion == 1 and .status == "local-pass" and
        .candidateSha == $sha and .candidateTree == $tree and
        .gateContractSha256 == $contract and .budgetsEnforced == true and
        .wireContract.version == 1 and
        (.wireContract.sha256 | test("^[0-9a-f]{64}$")) and
        (.binarySha256 | test("^[0-9a-f]{64}$")) and
        (.metadataSha256 | test("^[0-9a-f]{64}$")) and
        (.dependencyGraphSha256 | test("^[0-9a-f]{64}$")) and
        .agentVoiceProvenance.schemaVersion == 1 and
        .agentVoiceProvenance.repository == "agentvoice" and
        (.agentVoiceProvenance.commitSha | test("^[0-9a-f]{40}$")) and
        (.agentVoiceProvenance.treeSha | test("^[0-9a-f]{40}$")) and
        .agentVoiceProvenance.validator.repositoryPath ==
            "src/codpiece-artifact-validator-cli.ts" and
        (.agentVoiceProvenance.validator.sha256 | test("^[0-9a-f]{64}$")) and
        (.agentVoiceProvenance.dependencyFiles | type == "array" and length > 0) and
        any(.agentVoiceProvenance.dependencyFiles[];
            .repositoryPath == "package.json") and
        (any(.agentVoiceProvenance.dependencyFiles[];
            .repositoryPath == "bun.lock") or
         any(.agentVoiceProvenance.dependencyFiles[];
            .repositoryPath == "bun.lockb")) and
        all(.agentVoiceProvenance.dependencyFiles[];
            (.repositoryPath | type == "string" and length > 0) and
            (.sha256 | test("^[0-9a-f]{64}$")))
    ' "$local_receipt" >/dev/null \
    || die "local-build receipt does not prove $voice_sha under the current contract"
local_receipt_sha=$(shasum -a 256 "$local_receipt" | awk '{print $1}')
agentvoice_provenance=$(jq -c '.agentVoiceProvenance' "$local_receipt")
wire_contract_sha=$(jq -r '.wireContract.sha256' "$local_receipt")
binary_sha=$(jq -r '.binarySha256' "$local_receipt")
binary_version=$(jq -r '.binaryVersion' "$local_receipt")
jq -e \
    --arg sha "$voice_sha" \
    --arg tree "$voice_tree" \
    --arg contract "$contract_sha" \
    --arg localReceiptSha "$local_receipt_sha" \
    --arg wireContract "$wire_contract_sha" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --argjson agentVoiceProvenance "$agentvoice_provenance" '
        def sha256:
            type == "string" and test("^[0-9a-f]{64}$");
        def evidence_sha:
            if type == "string" then sha256
            elif type == "array" then all(.[]; sha256)
            elif . == null then true
            else false
            end;
        .schemaVersion == 1 and .status == "artifact-pass" and
        .candidateSha == $sha and .candidateTree == $tree and
        .gateContractSha256 == $contract and
        .localReceiptSha256 == $localReceiptSha and
        .agentVoiceProvenance == $agentVoiceProvenance and
        .agentVoice.schemaVersion == 1 and
        .agentVoice.status == "accepted" and
        .agentVoice.candidateSha == $sha and
        .agentVoice.binarySha256 == $binarySha and
        .agentVoice.binaryVersion == $binaryVersion and
        .agentVoice.wireContractSha256 == $wireContract and
        (.agentVoice.artifact.path | type == "string" and length > 0) and
        (.agentVoice.artifact.manifestSha256 | sha256) and
        (.agentVoice.artifact.eventsSha256 | sha256) and
        (.agentVoice.artifact.scenarioSha256 | sha256) and
        (.agentVoice.artifact.evaluationInputReceiptSha256 | sha256) and
        (.agentVoice.artifact.comparisonWavSha256 | sha256) and
        (.agentVoice.artifact.inputWavSha256 | sha256) and
        (.agentVoice.artifact.outputWavSha256 | sha256) and
        (.agentVoice.artifact.declaredEvidenceSha256 |
            type == "object" and length > 0) and
        all(.agentVoice.artifact.declaredEvidenceSha256[]; evidence_sha)
    ' "$artifact_receipt" >/dev/null \
    || die "artifact gate does not prove $voice_sha under the current contract"

if [ "$bootstrap_state" = create ]; then
    printf 'MAIN %s -> %s\n' "$fork_main_sha" "$upstream_sha"
    printf 'CREATE %s %s\n' "$voice_branch" "$voice_sha"
    printf 'CREATE integration %s\n' "$voice_sha"
else
    printf 'REPAIR-LOCAL %s %s\n' "$voice_branch" "$voice_sha"
    printf 'REPAIR-LOCAL integration %s\n' "$voice_sha"
fi
[ "$mode" = apply ] || exit 0

mkdir -p "$state_root"
chmod 0700 "$state_root"
lock_dir="$state_root/namespace.lock"
mkdir -m 0700 "$lock_dir" 2>/dev/null \
    || die "another branch publication owns $lock_dir"
printf '%s\n' "$$" >"$lock_dir/pid"

if [ "$bootstrap_state" = create ]; then
    # Re-read every leased target immediately before the optional race hook and
    # atomic push. The push leases remain the final authority.
    current_main=$(git -C "$checkout" ls-remote --heads fork refs/heads/main \
        | awk 'NR == 1 { print $1 }')
    [ "$current_main" = "$fork_main_sha" ] \
        || die "fork/main moved from $fork_main_sha to $current_main"
    [ -z "$(git -C "$checkout" ls-remote --heads fork refs/heads/integration)" ] \
        || die "fork/integration appeared during bootstrap"
    [ -z "$(git -C "$checkout" ls-remote --heads fork "refs/heads/$voice_branch")" ] \
        || die "fork/$voice_branch appeared during bootstrap"

    if [ "$test_mode" -eq 1 ] \
        && [ -n "${CODPIECE_BOOTSTRAP_BEFORE_PUSH_HOOK:-}" ]; then
        [ -x "$CODPIECE_BOOTSTRAP_BEFORE_PUSH_HOOK" ] \
            || die "bootstrap test hook is not executable"
        "$CODPIECE_BOOTSTRAP_BEFORE_PUSH_HOOK" "$actual_fork"
    fi

    git -C "$checkout" push --quiet --atomic fork \
        --force-with-lease="refs/heads/main:$fork_main_sha" \
        --force-with-lease=refs/heads/integration: \
        --force-with-lease="refs/heads/$voice_branch:" \
        "$upstream_sha:refs/heads/main" \
        "$voice_sha:refs/heads/$voice_branch" \
        "$voice_sha:refs/heads/integration" \
        || die "atomic bootstrap push failed; no target ref was accepted"

    if [ "$test_mode" -eq 1 ] \
        && [ -n "${CODPIECE_BOOTSTRAP_AFTER_PUSH_HOOK:-}" ]; then
        [ -x "$CODPIECE_BOOTSTRAP_AFTER_PUSH_HOOK" ] \
            || die "post-push bootstrap test hook is not executable"
        "$CODPIECE_BOOTSTRAP_AFTER_PUSH_HOOK" "$actual_fork" \
            || die "remote bootstrap published; local binding was interrupted"
    fi
else
    current_main=$(git -C "$checkout" ls-remote --heads fork refs/heads/main \
        | awk 'NR == 1 { print $1 }')
    current_integration=$(git -C "$checkout" ls-remote --heads fork \
        refs/heads/integration | awk 'NR == 1 { print $1 }')
    current_voice=$(git -C "$checkout" ls-remote --heads fork \
        "refs/heads/$voice_branch" | awk 'NR == 1 { print $1 }')
    [ "$current_main" = "$upstream_sha" ] \
        && [ "$current_integration" = "$voice_sha" ] \
        && [ "$current_voice" = "$voice_sha" ] \
        || die "remote bootstrap refs moved before local repair"
fi

git -C "$checkout" fetch --quiet --no-tags fork \
    '+refs/heads/main:refs/remotes/fork/main' \
    '+refs/heads/integration:refs/remotes/fork/integration' \
    "+refs/heads/$voice_branch:refs/remotes/fork/$voice_branch" \
    || die "bootstrap published, but local fork tracking refresh failed"
if [ "$local_integration_exists" -eq 0 ]; then
    git -C "$checkout" branch integration "$voice_sha" >/dev/null \
        || die "bootstrap published, but local integration creation failed"
fi
git -C "$checkout" branch --set-upstream-to=fork/integration integration >/dev/null \
    || die "bootstrap published, but local integration tracking failed"
git -C "$checkout" branch --set-upstream-to="fork/$voice_branch" \
    "$voice_branch" >/dev/null \
    || die "bootstrap published, but carry tracking failed"
git -C "$checkout" config branch.main.pushRemote fork
git -C "$checkout" config branch.integration.pushRemote fork
git -C "$checkout" config "branch.$voice_branch.pushRemote" fork

if [ "$bootstrap_state" = create ]; then
    printf 'BOOTSTRAPPED %s\n' "$voice_sha"
else
    printf 'REPAIRED-LOCAL %s\n' "$voice_sha"
fi
