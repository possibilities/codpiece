#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/build-lock.sh"
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece local gate: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/gate.sh --worktree PATH\n'
}

[ "${1:-}" = --worktree ] && [ "$#" -eq 2 ] || {
    usage >&2
    exit 64
}

worktree=$2
package=codex-voice-sidecar
state_root="${CODPIECE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codpiece}"

for command in cargo comm git jq just shasum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$worktree is not a git worktree"
worktree=$(cd "$worktree" && pwd -P)
manifest="$worktree/codex-rs/Cargo.toml"
[ -f "$manifest" ] || die "$manifest is missing"
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "$worktree has local changes; gate an exact committed candidate"

candidate_sha=$(git -C "$worktree" rev-parse HEAD)
codpiece_full_sha "$candidate_sha" || die "HEAD is not a full lowercase commit SHA"
candidate_tree=$(git -C "$worktree" rev-parse 'HEAD^{tree}')
upstream_ref=refs/remotes/origin/main
git -C "$worktree" rev-parse --verify --quiet "$upstream_ref^{commit}" >/dev/null \
    || die "$worktree has no origin/main tracking commit"
upstream_sha=$(git -C "$worktree" rev-parse "$upstream_ref")
git -C "$worktree" merge-base --is-ancestor "$upstream_sha" "$candidate_sha" \
    || die "$candidate_sha does not contain origin/main at $upstream_sha"
contract_sha=$(codpiece_gate_contract_digest "$root") \
    || die "could not hash the gate contract"
if [ -n "${CODPIECE_TARGET_DIR:-}" ]; then
    target_base=$CODPIECE_TARGET_DIR
elif [ -d /Volumes/Scratch ] && [ -w /Volumes/Scratch ]; then
    target_base=/Volumes/Scratch/codpiece/targets
else
    target_base="${XDG_CACHE_HOME:-$HOME/.cache}/codpiece/targets"
fi
target_dir="$target_base/$candidate_sha"
mkdir -p "$target_dir"

export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR="$target_dir"
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_INCREMENTAL=0

tree_file=$(mktemp "${TMPDIR:-/tmp}/codpiece-tree.XXXXXX")
package_file=$(mktemp "${TMPDIR:-/tmp}/codpiece-packages.XXXXXX")
first_party_file=$(mktemp "${TMPDIR:-/tmp}/codpiece-first-party.XXXXXX")
pending_receipt=
pending_metadata=
lock_held=0
cleanup() {
    local status=$? cleanup_failed=0
    trap - EXIT
    rm -f -- "$tree_file" "$package_file" "$first_party_file" || cleanup_failed=1
    if [ -n "$pending_receipt" ] && [ -e "$pending_receipt" ]; then
        rm -f -- "$pending_receipt" || cleanup_failed=1
    fi
    if [ -n "$pending_metadata" ] && [ -e "$pending_metadata" ]; then
        rm -f -- "$pending_metadata" || cleanup_failed=1
    fi
    if [ "$lock_held" -eq 1 ]; then
        codpiece_release_lock_release || cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'codpiece local gate: cleanup failed\n' >&2
        [ "$status" -ne 0 ] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT

codpiece_release_lock_acquire "$state_root" || die "release lock is busy"
lock_held=1

printf 'LOCAL-BUILD %-24s %s\n' tests "$candidate_sha"
(cd "$worktree/codex-rs" && just test -p "$package")
(cd "$worktree/codex-rs" && just fix -p "$package")
(cd "$worktree/codex-rs" && just fmt)
[ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "just fix or just fmt changed the candidate; review and commit those changes before gating"

cargo tree --locked --manifest-path "$manifest" -p "$package" \
    --edges normal,build --prefix none --format '{p}' >"$tree_file"
dependency_graph_sha=$(shasum -a 256 "$tree_file" | awk '{print $1}')
sed 's/ (\*)$//; /^[[:space:]]*$/d' "$tree_file" \
    | LC_ALL=C sort -u >"$package_file"
dependency_count=$(wc -l <"$package_file" | tr -d ' ')
[ "$dependency_count" -gt 0 ] || die "could not measure the resolved dependency graph"

awk '$1 ~ /^codex-/ { print $1 }' "$package_file" \
    | LC_ALL=C sort -u >"$first_party_file"
undeclared=$(comm -23 "$first_party_file" \
    <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
        "$root/gate/first-party-allowlist.txt" | LC_ALL=C sort -u))
[ -z "$undeclared" ] \
    || die "undeclared first-party dependencies: $(printf '%s' "$undeclared" | tr '\n' ' ')"

for forbidden in \
    codex-agent-graph-store \
    codex-app-server \
    codex-app-server-client \
    codex-app-server-daemon \
    codex-app-server-protocol \
    codex-app-server-transport \
    codex-apply-patch \
    codex-code-mode \
    codex-core \
    codex-exec \
    codex-exec-server \
    codex-history \
    codex-linux-sandbox \
    codex-mcp \
    codex-mcp-server \
    codex-message-history \
    codex-protocol \
    codex-responses-api-proxy \
    codex-rmcp-client \
    codex-rollout \
    codex-rollout-trace \
    codex-sandboxing \
    codex-skills \
    codex-state \
    codex-thread-store \
    codex-tools \
    codex-worktree; do
    if grep -Fx "$forbidden" "$first_party_file" >/dev/null; then
        die "$package depends on forbidden package $forbidden"
    fi
done

printf 'LOCAL-BUILD %-24s %s packages\n' dependency-boundary "$dependency_count"
cargo build --locked --manifest-path "$manifest" -p "$package" --release
binary="$target_dir/release/$package"
[ -x "$binary" ] || die "release binary was not produced at $binary"
binary_version=$("$binary" --version)
[ -n "$binary_version" ] || die "release binary reported no version"
if binary_size=$(stat -f %z "$binary" 2>/dev/null); then
    :
else
    binary_size=$(stat -c %s "$binary")
fi
binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')

binary_budget=$(jq -r '.binaryBytesMax // empty' "$root/gate/budgets.json")
dependency_budget=$(jq -r '.dependencyCountMax // empty' "$root/gate/budgets.json")
budgets_enforced=false
receipt_status=measured
if [ -n "$binary_budget" ] && [ -n "$dependency_budget" ]; then
    [ "$binary_size" -le "$binary_budget" ] \
        || die "binary is $binary_size bytes, over the $binary_budget-byte budget"
    [ "$dependency_count" -le "$dependency_budget" ] \
        || die "dependency graph has $dependency_count packages, over the $dependency_budget-package budget"
    budgets_enforced=true
    receipt_status=local-pass
fi

git -C "$worktree" diff --quiet \
    || die "candidate worktree changed during the gate"
git -C "$worktree" diff --cached --quiet \
    || die "candidate index changed during the gate"
[ "$(git -C "$worktree" rev-parse HEAD)" = "$candidate_sha" ] \
    || die "candidate HEAD moved during the gate"

recorded_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
metadata="$target_dir/release/metadata.json"
pending_metadata=$(mktemp "$target_dir/release/.metadata.XXXXXX")
jq -n \
    --arg sourceRevision "$candidate_sha" \
    --arg upstreamRevision "$upstream_sha" \
    --arg builtAt "$recorded_at" \
    --arg binarySha256 "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    '{schemaVersion:3,implementation:"codex-voice-sidecar",
      sourceRepository:"possibilities/codex",sourceRevision:$sourceRevision,
      upstreamRevision:$upstreamRevision,builtAt:$builtAt,
      binarySha256:$binarySha256,binaryVersion:$binaryVersion,
      credentialAuthority:{owner:"fx",provider:"codex",
        transport:"inherited-fd",descriptor:3,protocolVersion:1,
        maxFrameBytes:65536}}' \
    >"$pending_metadata"
chmod 0600 "$pending_metadata"
mv "$pending_metadata" "$metadata"
pending_metadata=
metadata_sha=$(shasum -a 256 "$metadata" | awk '{print $1}')

receipt_dir="$state_root/local-builds"
mkdir -p "$receipt_dir"
chmod 0700 "$receipt_dir"
receipt="$receipt_dir/$candidate_sha.json"
umask 077
pending_receipt=$(mktemp "$receipt_dir/.$candidate_sha.XXXXXX")
jq -n \
    --arg status "$receipt_status" \
    --arg candidateSha "$candidate_sha" \
    --arg candidateTree "$candidate_tree" \
    --arg upstreamSha "$upstream_sha" \
    --arg gateContractSha256 "$contract_sha" \
    --arg binary "$binary" \
    --arg binarySha256 "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg metadata "$metadata" \
    --arg metadataSha256 "$metadata_sha" \
    --arg dependencyGraphSha256 "$dependency_graph_sha" \
    --arg recordedAt "$recorded_at" \
    --argjson binaryBytes "$binary_size" \
    --argjson dependencyCount "$dependency_count" \
    --argjson budgetsEnforced "$budgets_enforced" \
    '{schemaVersion:1,status:$status,candidateSha:$candidateSha,
      candidateTree:$candidateTree,upstream:{ref:"origin/main",sha:$upstreamSha},
      gateContractSha256:$gateContractSha256,
      package:"codex-voice-sidecar",binary:$binary,
      binarySha256:$binarySha256,binaryVersion:$binaryVersion,
      binaryBytes:$binaryBytes,metadata:$metadata,
      metadataSha256:$metadataSha256,
      dependencyCount:$dependencyCount,
      dependencyGraphSha256:$dependencyGraphSha256,
      budgetsEnforced:$budgetsEnforced,
      build:{cargoJobs:2,releaseLto:false,releaseCodegenUnits:1,
        releaseStrip:"symbols"},
      recordedAt:$recordedAt}' >"$pending_receipt"
chmod 0600 "$pending_receipt"
mv "$pending_receipt" "$receipt"
pending_receipt=

if [ "$budgets_enforced" != true ]; then
    printf 'MEASURED %s: set binaryBytesMax >= %s and dependencyCountMax >= %s, then rerun; this receipt cannot ship\n' \
        "$candidate_sha" "$binary_size" "$dependency_count"
else
    printf 'LOCAL-PASS %s (%s bytes, %s packages, %s)\n' \
        "$candidate_sha" "$binary_size" "$dependency_count" "$binary_version"
fi
printf 'RECEIPT %s\n' "$receipt"
