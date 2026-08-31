#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/build-lock.sh"
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece ship gate: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/ship-gate.sh --worktree PATH --sha SHA\n'
}

worktree=
expected_sha=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --worktree)
            [ "$#" -ge 2 ] || die "--worktree requires a path"
            worktree=$2
            shift 2
            ;;
        --sha)
            [ "$#" -ge 2 ] || die "--sha requires a commit"
            expected_sha=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done
[ -n "$worktree" ] || die "--worktree is required"
[ -n "$expected_sha" ] || die "--sha is required"
codpiece_full_sha "$expected_sha" || die "--sha must be a full lowercase commit SHA"

for command in bun cmp git jq shasum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$worktree is not a git worktree"
worktree=$(cd "$worktree" && pwd -P)
[ "$(git -C "$worktree" rev-parse HEAD)" = "$expected_sha" ] \
    || die "worktree is not at $expected_sha"
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "worktree has local changes"

test_mode="${CODPIECE_TESTING:-0}"
case "$test_mode" in 0|1) ;; *) die "CODPIECE_TESTING must be 0 or 1" ;; esac
actual_fork=$(git -C "$worktree" remote get-url fork 2>/dev/null) \
    || die "$worktree has no fork remote"
actual_origin=$(git -C "$worktree" remote get-url origin 2>/dev/null) \
    || die "$worktree has no origin remote"
if [ "$test_mode" -eq 0 ]; then
    codpiece_remote_matches "$actual_fork" "$CODPIECE_CANONICAL_FORK_URL" \
        || die "$worktree fork remote points at $actual_fork"
    codpiece_remote_matches "$actual_origin" "$CODPIECE_CANONICAL_UPSTREAM_URL" \
        || die "$worktree origin remote points at $actual_origin"
else
    codpiece_require_local_test_remote fork "$actual_fork" \
        || die "test mode remote safety check failed"
    codpiece_require_local_test_remote origin "$actual_origin" \
        || die "test mode remote safety check failed"
fi

remote_integration() {
    codpiece_remote_head "$worktree" fork refs/heads/integration fork/integration \
        || die "could not read fork/integration"
}

remote_origin_main() {
    codpiece_remote_head "$worktree" origin refs/heads/main origin/main \
        || die "could not read origin/main"
}

published_sha=$(remote_integration)
[ "$published_sha" = "$expected_sha" ] \
    || die "fork/integration is $published_sha, expected $expected_sha"

state_root="${CODPIECE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codpiece}"
validator_output=
expected_validation=
pending_receipt=
lock_held=0
cleanup() {
    local status=$? cleanup_failed=0
    trap - EXIT
    for temporary in "$validator_output" "$expected_validation"; do
        if [ -n "$temporary" ] && [ -e "$temporary" ]; then
            rm -f -- "$temporary" || cleanup_failed=1
        fi
    done
    if [ -n "$pending_receipt" ] && [ -e "$pending_receipt" ]; then
        rm -f -- "$pending_receipt" || cleanup_failed=1
    fi
    if [ "$lock_held" -eq 1 ]; then
        codpiece_release_lock_release || cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'codpiece ship gate: cleanup failed\n' >&2
        [ "$status" -ne 0 ] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
codpiece_release_lock_acquire "$state_root" || die "release lock is busy"
lock_held=1

local_receipt="$state_root/local-builds/$expected_sha.json"
artifact_receipt="$state_root/artifact-gates/$expected_sha.json"
codpiece_regular_private_receipt "$local_receipt" \
    || die "no private regular local-build receipt for $expected_sha"
codpiece_regular_private_receipt "$artifact_receipt" \
    || die "no private regular artifact-gate receipt for $expected_sha"
contract_sha=$(codpiece_gate_contract_digest "$root") \
    || die "could not hash the gate contract"
candidate_tree=$(git -C "$worktree" rev-parse 'HEAD^{tree}')
local_receipt_sha=$(shasum -a 256 "$local_receipt" | awk '{print $1}')
jq -e \
    --arg sha "$expected_sha" \
    --arg tree "$candidate_tree" \
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
    || die "local-build receipt does not prove this candidate under the current contract"
expected_agentvoice_provenance=$(jq -c '.agentVoiceProvenance' "$local_receipt")
wire_contract_sha=$(jq -r '.wireContract.sha256' "$local_receipt")
binary_sha=$(jq -r '.binarySha256' "$local_receipt")
binary_version=$(jq -r '.binaryVersion' "$local_receipt")
metadata_sha=$(jq -r '.metadataSha256' "$local_receipt")
jq -e \
    --arg sha "$expected_sha" \
    --arg tree "$candidate_tree" \
    --arg contract "$contract_sha" \
    --arg localReceiptSha "$local_receipt_sha" \
    --arg wireContract "$wire_contract_sha" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --argjson agentVoiceProvenance "$expected_agentvoice_provenance" '
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
    || die "artifact receipt does not prove this candidate under the current contract"

binary=$(jq -r '.binary' "$local_receipt")
metadata=$(jq -r '.metadata' "$local_receipt")
[ -f "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ] \
    || die "gated binary is not a regular executable"
[ "$(shasum -a 256 "$binary" | awk '{print $1}')" = "$binary_sha" ] \
    || die "gated binary changed after artifact validation"
[ "$("$binary" --version)" = "$binary_version" ] \
    || die "gated binary version changed after artifact validation"
[ -f "$metadata" ] && [ ! -L "$metadata" ] \
    || die "gated sidecar metadata is not a regular file"
[ "$(shasum -a 256 "$metadata" | awk '{print $1}')" = \
    "$metadata_sha" ] \
    || die "gated sidecar metadata changed after artifact validation"
jq -e \
    --arg sha "$expected_sha" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg wireContract "$wire_contract_sha" '
        .schemaVersion == 2 and
        .implementation == "codex-voice-sidecar" and
        .sourceRevision == $sha and
        .wireContractSha256 == $wireContract and
        .binarySha256 == $binarySha and
        .binaryVersion == $binaryVersion
    ' "$metadata" >/dev/null || die "gated sidecar metadata is invalid"

upstream_sha=$(remote_origin_main)
[ "$upstream_sha" = "$(jq -r '.upstream.sha' "$local_receipt")" ] \
    || die "local build covered a different origin/main commit"
git -C "$worktree" merge-base --is-ancestor "$upstream_sha" "$expected_sha" \
    || die "$expected_sha does not contain current origin/main at $upstream_sha"

artifact=$(jq -r '.agentVoice.artifact.path' "$artifact_receipt")
agentvoice_root="${CODPIECE_AGENTVOICE_ROOT:-$HOME/code/agentvoice}"
validator="$agentvoice_root/src/codpiece-artifact-validator-cli.ts"
[ -f "$validator" ] || die "AgentVoice native validator is missing at $validator"
agentvoice_provenance=$(codpiece_agentvoice_provenance "$agentvoice_root" "$validator") \
    || die "could not bind a clean exact AgentVoice validator provenance"
jq -e -S \
    --argjson expected "$expected_agentvoice_provenance" \
    --argjson current "$agentvoice_provenance" \
    -n '$expected == $current' >/dev/null \
    || die "current AgentVoice provenance does not match the artifact-gate receipt"
validator_output=$(mktemp "${TMPDIR:-/tmp}/codpiece-ship-validation.XXXXXX")
expected_validation=$(mktemp "${TMPDIR:-/tmp}/codpiece-ship-expected.XXXXXX")

(
    cd "$agentvoice_root"
    bun run "$validator" \
        --artifact "$artifact" \
        --binary "$binary" \
        --candidate-sha "$expected_sha"
) >"$validator_output" || die "AgentVoice no longer accepts the artifact"
jq -S '.agentVoice' "$artifact_receipt" >"$expected_validation"
jq -S . "$validator_output" | cmp -s - "$expected_validation" \
    || die "AgentVoice validation no longer matches the artifact-gate receipt"
agentvoice_provenance_after=$(codpiece_agentvoice_provenance "$agentvoice_root" "$validator") \
    || die "AgentVoice validator provenance changed or became dirty"
jq -e -S \
    --argjson before "$agentvoice_provenance" \
    --argjson after "$agentvoice_provenance_after" \
    -n '$before == $after' >/dev/null \
    || die "AgentVoice validator provenance changed during ship validation"

# No network or long-running command follows these final identity checks.
[ "$(git -C "$worktree" rev-parse HEAD)" = "$expected_sha" ] \
    || die "candidate HEAD moved during the ship gate"
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "candidate worktree changed during the ship gate"
published_sha=$(remote_integration)
[ "$published_sha" = "$expected_sha" ] \
    || die "fork/integration moved to $published_sha during the ship gate"

artifact_receipt_sha=$(shasum -a 256 "$artifact_receipt" | awk '{print $1}')
recorded_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
receipt_dir="$state_root/ship-gates"
mkdir -p "$receipt_dir"
chmod 0700 "$receipt_dir"
receipt="$receipt_dir/$expected_sha.json"
umask 077
pending_receipt=$(mktemp "$receipt_dir/.$expected_sha.XXXXXX")
jq -n \
    --arg candidateSha "$expected_sha" \
    --arg candidateTree "$candidate_tree" \
    --arg upstreamSha "$upstream_sha" \
    --arg gateContractSha256 "$contract_sha" \
    --arg localReceiptSha256 "$local_receipt_sha" \
    --arg artifactReceiptSha256 "$artifact_receipt_sha" \
    --arg binarySha256 "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg metadataSha256 "$metadata_sha" \
    --arg recordedAt "$recorded_at" \
    --argjson agentVoiceProvenance "$agentvoice_provenance" \
    --slurpfile agentVoice "$validator_output" \
    --slurpfile sidecarMetadata "$metadata" \
    '{schemaVersion:1,status:"ship",candidateSha:$candidateSha,
      candidateTree:$candidateTree,source:"possibilities/codex:integration",
      upstreamSha:$upstreamSha,gateContractSha256:$gateContractSha256,
      localReceiptSha256:$localReceiptSha256,
      artifactReceiptSha256:$artifactReceiptSha256,
      binarySha256:$binarySha256,binaryVersion:$binaryVersion,
      metadataSha256:$metadataSha256,
      agentVoiceProvenance:$agentVoiceProvenance,
      sidecarMetadata:$sidecarMetadata[0],agentVoice:$agentVoice[0],
      recordedAt:$recordedAt}' \
    >"$pending_receipt"
chmod 0600 "$pending_receipt"
if [ -e "$receipt" ] || [ -L "$receipt" ]; then
    codpiece_regular_private_receipt "$receipt" \
        || die "existing ship receipt is not a private regular file"
    cmp -s \
        <(jq -S 'del(.recordedAt)' "$receipt") \
        <(jq -S 'del(.recordedAt)' "$pending_receipt") \
        || die "existing ship receipt proves different inputs"
    rm -f -- "$pending_receipt"
else
    mv "$pending_receipt" "$receipt"
fi
pending_receipt=

codpiece_release_lock_release || die "could not release the ship-gate lock"
lock_held=0

printf 'SHIP %s\n' "$expected_sha"
printf 'RECEIPT %s\n' "$receipt"
