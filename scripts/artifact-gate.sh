#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/build-lock.sh"
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece artifact gate: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/artifact-gate.sh --worktree PATH --sha SHA --artifact PATH\n'
}

worktree=
expected_sha=
artifact=
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
        --artifact)
            [ "$#" -ge 2 ] || die "--artifact requires a path"
            artifact=$2
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
[ -n "$artifact" ] || die "--artifact is required"
codpiece_full_sha "$expected_sha" || die "--sha must be a full lowercase commit SHA"

for command in bun git jq shasum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$worktree is not a git worktree"
worktree=$(cd "$worktree" && pwd -P)
[ "$(git -C "$worktree" rev-parse HEAD)" = "$expected_sha" ] \
    || die "worktree is not at $expected_sha"
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "worktree has local changes"
[ -d "$artifact" ] || die "artifact directory does not exist: $artifact"
artifact=$(cd "$artifact" && pwd -P)

state_root="${CODPIECE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codpiece}"
validator_output=
pending_receipt=
lock_held=0
cleanup() {
    local status=$? cleanup_failed=0
    trap - EXIT
    if [ -n "$validator_output" ] && [ -e "$validator_output" ]; then
        rm -f -- "$validator_output" || cleanup_failed=1
    fi
    if [ -n "$pending_receipt" ] && [ -e "$pending_receipt" ]; then
        rm -f -- "$pending_receipt" || cleanup_failed=1
    fi
    if [ "$lock_held" -eq 1 ]; then
        codpiece_release_lock_release || cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'codpiece artifact gate: cleanup failed\n' >&2
        [ "$status" -ne 0 ] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
codpiece_release_lock_acquire "$state_root" || die "release lock is busy"
lock_held=1

local_receipt="$state_root/local-builds/$expected_sha.json"
codpiece_regular_private_receipt "$local_receipt" \
    || die "no private regular local-build receipt for $expected_sha"
contract_sha=$(codpiece_gate_contract_digest "$root") \
    || die "could not hash the gate contract"
candidate_tree=$(git -C "$worktree" rev-parse 'HEAD^{tree}')
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

binary=$(jq -r '.binary' "$local_receipt")
metadata=$(jq -r '.metadata' "$local_receipt")
[ -f "$binary" ] && [ -x "$binary" ] && [ ! -L "$binary" ] \
    || die "gated binary is not a regular executable: $binary"
[ -f "$metadata" ] && [ ! -L "$metadata" ] \
    || die "gated metadata is not a regular file: $metadata"
binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')
metadata_sha=$(shasum -a 256 "$metadata" | awk '{print $1}')
[ "$binary_sha" = "$(jq -r '.binarySha256' "$local_receipt")" ] \
    || die "gated binary changed after the local build"
[ "$metadata_sha" = "$(jq -r '.metadataSha256' "$local_receipt")" ] \
    || die "gated metadata changed after the local build"
binary_version=$("$binary" --version)
[ "$binary_version" = "$(jq -r '.binaryVersion' "$local_receipt")" ] \
    || die "gated binary version changed after the local build"
wire_contract_sha=$(jq -r '.wireContract.sha256' "$local_receipt")
expected_agentvoice_provenance=$(jq -c '.agentVoiceProvenance' "$local_receipt")

agentvoice_root="${CODPIECE_AGENTVOICE_ROOT:-$HOME/code/agentvoice}"
validator="$agentvoice_root/src/codpiece-artifact-validator-cli.ts"
[ -f "$validator" ] || die "AgentVoice native validator is missing at $validator"
agentvoice_provenance=$(codpiece_agentvoice_provenance "$agentvoice_root" "$validator") \
    || die "could not bind a clean exact AgentVoice validator provenance"
jq -e -S \
    --argjson expected "$expected_agentvoice_provenance" \
    --argjson current "$agentvoice_provenance" \
    -n '$expected == $current' >/dev/null \
    || die "current AgentVoice provenance does not match the local-build receipt"
validator_output=$(mktemp "${TMPDIR:-/tmp}/codpiece-artifact-validation.XXXXXX")

(
    cd "$agentvoice_root"
    bun run "$validator" \
        --artifact "$artifact" \
        --binary "$binary" \
        --candidate-sha "$expected_sha"
) >"$validator_output" \
    || die "AgentVoice rejected the live full-duplex artifact"
jq -e \
    --arg sha "$expected_sha" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg wireContract "$wire_contract_sha" '
        def sha:
            type == "string" and test("^[0-9a-f]{64}$");
        def evidence_sha:
            if type == "string" then sha
            elif type == "array" then all(.[]; sha)
            elif . == null then true
            else false
            end;
        .schemaVersion == 1 and .status == "accepted" and
        .candidateSha == $sha and .binarySha256 == $binarySha and
        .binaryVersion == $binaryVersion and
        .wireContractSha256 == $wireContract and
        (.artifact.manifestSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.eventsSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.scenarioSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.evaluationInputReceiptSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.comparisonWavSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.inputWavSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.outputWavSha256 | test("^[0-9a-f]{64}$")) and
        (.artifact.declaredEvidenceSha256 | type == "object" and length > 0) and
        all(.artifact.declaredEvidenceSha256[]; evidence_sha)
    ' "$validator_output" >/dev/null \
    || die "AgentVoice validator returned an incomplete receipt"
agentvoice_provenance_after=$(codpiece_agentvoice_provenance "$agentvoice_root" "$validator") \
    || die "AgentVoice validator provenance changed or became dirty"
jq -e -S \
    --argjson before "$agentvoice_provenance" \
    --argjson after "$agentvoice_provenance_after" \
    -n '$before == $after' >/dev/null \
    || die "AgentVoice validator provenance changed during artifact validation"

[ "$(git -C "$worktree" rev-parse HEAD)" = "$expected_sha" ] \
    || die "candidate HEAD moved during artifact validation"
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "candidate worktree changed during artifact validation"
[ "$(shasum -a 256 "$binary" | awk '{print $1}')" = "$binary_sha" ] \
    || die "gated binary changed during artifact validation"
[ "$(shasum -a 256 "$metadata" | awk '{print $1}')" = "$metadata_sha" ] \
    || die "gated metadata changed during artifact validation"

local_receipt_sha=$(shasum -a 256 "$local_receipt" | awk '{print $1}')
recorded_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
receipt_dir="$state_root/artifact-gates"
mkdir -p "$receipt_dir"
chmod 0700 "$receipt_dir"
receipt="$receipt_dir/$expected_sha.json"
umask 077
pending_receipt=$(mktemp "$receipt_dir/.$expected_sha.XXXXXX")
jq -n \
    --arg candidateSha "$expected_sha" \
    --arg candidateTree "$candidate_tree" \
    --arg gateContractSha256 "$contract_sha" \
    --arg localReceipt "$local_receipt" \
    --arg localReceiptSha256 "$local_receipt_sha" \
    --arg recordedAt "$recorded_at" \
    --argjson agentVoiceProvenance "$agentvoice_provenance" \
    --slurpfile agentVoice "$validator_output" \
    '{schemaVersion:1,status:"artifact-pass",candidateSha:$candidateSha,
      candidateTree:$candidateTree,gateContractSha256:$gateContractSha256,
      localReceipt:$localReceipt,localReceiptSha256:$localReceiptSha256,
      agentVoiceProvenance:$agentVoiceProvenance,
      agentVoice:$agentVoice[0],recordedAt:$recordedAt}' \
    >"$pending_receipt"
chmod 0600 "$pending_receipt"
mv "$pending_receipt" "$receipt"
pending_receipt=

codpiece_release_lock_release || die "could not release the artifact-gate lock"
lock_held=0

printf 'ARTIFACT-PASS %s %s\n' "$expected_sha" "$artifact"
printf 'RECEIPT %s\n' "$receipt"
