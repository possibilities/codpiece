#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/build-lock.sh"
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece installer: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/install.sh --check|--install --sha FULL_SHA\n'
}

mode=
expected_sha=
case "${1:-}" in
    --check)
        [ "$#" -eq 1 ] || {
            usage >&2
            exit 64
        }
        mode=check
        ;;
    --install)
        [ "$#" -eq 3 ] && [ "${2:-}" = --sha ] || {
            usage >&2
            exit 64
        }
        mode=install
        expected_sha=$3
        codpiece_full_sha "$expected_sha" \
            || die "--sha must be a full lowercase commit SHA"
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

checkout="${CODPIECE_CODEX_CHECKOUT:-$HOME/src/codex}"
package=codex-voice-sidecar
install_root="${CODPIECE_INSTALL_ROOT:-$HOME/.local/lib/codpiece}"
binary_link="${CODPIECE_BINARY_LINK:-$HOME/.local/bin/codex-voice-sidecar}"
current_link="$install_root/current"
installed_receipt="$current_link/install.json"
state_root="${CODPIECE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codpiece}"
test_mode="${CODPIECE_TESTING:-0}"
case "$test_mode" in 0|1) ;; *) die "CODPIECE_TESTING must be 0 or 1" ;; esac
if [ "$test_mode" -eq 1 ] && [ -n "${CODPIECE_FORK_URL:-}" ]; then
    display_fork_url=$CODPIECE_FORK_URL
else
    display_fork_url=$CODPIECE_CANONICAL_FORK_URL
fi

if [ -n "${CODPIECE_TARGET_DIR:-}" ]; then
    target_base=$CODPIECE_TARGET_DIR
elif [ -d /Volumes/Scratch ] && [ -w /Volumes/Scratch ]; then
    target_base=/Volumes/Scratch/codpiece/targets
else
    target_base="${XDG_CACHE_HOME:-$HOME/.cache}/codpiece/targets"
fi

if [ "$mode" = check ]; then
    printf '%s\n' \
        'codpiece installation:' \
        "  checkout: $checkout" \
        "  source: fork/integration ($display_fork_url), exact full SHA only" \
        '  authority: current-contract local-build receipt for this exact candidate' \
        "  build: detached $package, two Cargo jobs, release LTO off, one codegen unit, symbols stripped" \
        "  target: SHA-isolated directories under $target_base" \
        "  install: immutable version under $install_root" \
        "  atomic consumer pointer: $current_link" \
        "  binary link: $binary_link -> $current_link/$package" \
        "  installed receipt: $installed_receipt"
    exit 0
fi

[ "$(id -u)" -ne 0 ] || die "run as the target user, not root"
for command in cargo git jq shasum; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$checkout is not a Git worktree"
[ -z "$(git -C "$checkout" status --porcelain)" ] \
    || die "$checkout has local changes; refusing to consume it"

actual_fork_url=$(git -C "$checkout" remote get-url fork 2>/dev/null) \
    || die "$checkout has no fork remote"
if [ "$test_mode" -eq 0 ]; then
    codpiece_remote_matches "$actual_fork_url" "$CODPIECE_CANONICAL_FORK_URL" \
        || die "$checkout fork remote is $actual_fork_url, not $CODPIECE_CANONICAL_FORK_URL"
else
    codpiece_require_local_test_remote fork "$actual_fork_url" \
        || die "test mode remote safety check failed"
fi

local_receipt="$state_root/local-builds/$expected_sha.json"

remote_integration() {
    codpiece_remote_head "$checkout" fork refs/heads/integration fork/integration \
        || die "could not read fork/integration"
}

mkdir -p "$target_base" "$install_root/versions" "$(dirname "$binary_link")"
lock_held=0
temp_root=
build_worktree=
staging="$install_root/.staging.$expected_sha.$$"
current_tmp="$install_root/.current.$$"
binary_link_tmp="$(dirname "$binary_link")/.$(basename "$binary_link").$$"
worktree_added=0
activated=0
old_current_present=0
old_current_target=
binary_link_created=0

rollback_current() {
    local restore_tmp
    restore_tmp="$install_root/.current.rollback.$$"
    rm -f -- "$restore_tmp"
    if [ "$old_current_present" -eq 1 ]; then
        ln -s "$old_current_target" "$restore_tmp" || return 1
        mv -fh "$restore_tmp" "$current_link" || return 1
    else
        rm -f -- "$current_link" || return 1
    fi
}

cleanup() {
    local status=$? cleanup_failed=0
    trap - EXIT
    if [ "$status" -ne 0 ] && [ "$activated" -eq 1 ]; then
        rollback_current || cleanup_failed=1
    fi
    if [ "$status" -ne 0 ] && [ "$binary_link_created" -eq 1 ]; then
        rm -f -- "$binary_link" || cleanup_failed=1
    fi
    if [ "$worktree_added" -eq 1 ] && [ -n "$build_worktree" ]; then
        git -C "$checkout" worktree remove --force "$build_worktree" \
            >/dev/null 2>&1 || cleanup_failed=1
    fi
    if [ -d "$staging" ]; then
        rm -rf -- "$staging" || cleanup_failed=1
    fi
    rm -f -- "$current_tmp" "$binary_link_tmp" || cleanup_failed=1
    if [ -n "$temp_root" ] && [ -d "$temp_root" ]; then
        rmdir "$temp_root" >/dev/null 2>&1 || cleanup_failed=1
    fi
    if [ "$lock_held" -eq 1 ]; then
        codpiece_release_lock_release || cleanup_failed=1
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
        printf 'codpiece installer: cleanup or rollback failed\n' >&2
        [ "$status" -ne 0 ] || status=1
    fi
    exit "$status"
}
trap cleanup EXIT

codpiece_release_lock_acquire "$state_root" || die "release lock is busy"
lock_held=1
codpiece_regular_private_receipt "$local_receipt" \
    || die "no private regular local-build receipt for $expected_sha"
contract_sha=$(codpiece_gate_contract_digest "$root") \
    || die "could not hash the gate contract"
local_receipt_sha=$(shasum -a 256 "$local_receipt" | awk '{print $1}')
jq -e \
    --arg sha "$expected_sha" \
    --arg contract "$contract_sha" '
        .schemaVersion == 1 and .status == "local-pass" and
        .candidateSha == $sha and
        (.candidateTree | test("^[0-9a-f]{40}$")) and
        .gateContractSha256 == $contract and .budgetsEnforced == true and
        (.binarySha256 | test("^[0-9a-f]{64}$")) and
        (.metadataSha256 | test("^[0-9a-f]{64}$")) and
        (.dependencyGraphSha256 | test("^[0-9a-f]{64}$"))
    ' "$local_receipt" >/dev/null \
    || die "local-build receipt does not prove this candidate under the current contract"
candidate_tree=$(jq -r '.candidateTree' "$local_receipt")
local_upstream_sha=$(jq -r '.upstream.sha' "$local_receipt")
expected_binary_sha=$(jq -r '.binarySha256' "$local_receipt")
expected_binary_version=$(jq -r '.binaryVersion' "$local_receipt")
expected_metadata_sha=$(jq -r '.metadataSha256' "$local_receipt")
metadata_source=$(jq -r '.metadata' "$local_receipt")
codpiece_regular_private_receipt "$metadata_source" \
    || die "local-build metadata is not a private regular file"
[ "$(shasum -a 256 "$metadata_source" | awk '{print $1}')" = "$expected_metadata_sha" ] \
    || die "local-build metadata bytes do not match the local receipt"
# The sidecar's own metadata says what this binary is; the build gate bound
# it to the candidate and its hashes, so it is what the installer verifies.
jq -e \
    --arg sha "$expected_sha" \
    --arg binarySha "$expected_binary_sha" \
    --arg binaryVersion "$expected_binary_version" \
    --arg upstreamSha "$local_upstream_sha" '
        .schemaVersion == 3 and
        .implementation == "codex-voice-sidecar" and
        .sourceRepository == "possibilities/codex" and
        .sourceRevision == $sha and
        .upstreamRevision == $upstreamSha and
        .binarySha256 == $binarySha and
        .binaryVersion == $binaryVersion and
        .credentialAuthority.owner == "fx" and
        .credentialAuthority.provider == "codex" and
        .credentialAuthority.transport == "inherited-fd" and
        .credentialAuthority.descriptor == 3
    ' "$metadata_source" >/dev/null \
    || die "sidecar metadata does not describe this candidate"
published=$(remote_integration)
[ "$published" = "$expected_sha" ] \
    || die "fork/integration is $published, not requested $expected_sha"
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/codpiece-install.XXXXXX")
build_worktree="$temp_root/codex"

git -C "$checkout" fetch --quiet --no-tags fork refs/heads/integration \
    || die "fetching fork/integration failed"
[ "$(git -C "$checkout" rev-parse FETCH_HEAD)" = "$expected_sha" ] \
    || die "fetched Integration does not match $expected_sha"
[ "$(git -C "$checkout" rev-parse "$expected_sha^{tree}")" = "$candidate_tree" ] \
    || die "fetched Integration tree does not match the local-build receipt"
git -C "$checkout" worktree add --quiet --detach "$build_worktree" "$expected_sha" \
    || die "could not create a detached worktree for $expected_sha"
worktree_added=1
manifest="$build_worktree/codex-rs/Cargo.toml"
[ -f "$manifest" ] || die "$manifest is missing"

target_dir="$target_base/reproductions/$expected_sha"
mkdir -p "$target_dir"
export CARGO_BUILD_JOBS=2
export CARGO_TARGET_DIR="$target_dir"
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_INCREMENTAL=0
cargo build --locked --manifest-path "$manifest" -p "$package" --release
built_binary="$target_dir/release/$package"
[ -x "$built_binary" ] || die "$built_binary was not produced"
binary_version=$("$built_binary" --version)
[ "$binary_version" = "$expected_binary_version" ] \
    || die "rebuilt binary reports $binary_version, expected $expected_binary_version"
binary_sha=$(shasum -a 256 "$built_binary" | awk '{print $1}')
[ "$binary_sha" = "$expected_binary_sha" ] \
    || die "rebuilt binary hash $binary_sha does not match gated hash $expected_binary_sha"

# Cleanup is blocking and happens before any consumer pointer can move.
git -C "$checkout" worktree remove --force "$build_worktree" \
    || die "could not remove detached build worktree"
worktree_added=0
rmdir "$temp_root" || die "detached build root is not empty after cleanup"

version_dir="$install_root/versions/$expected_sha"
immutable_binary="$version_dir/$package"
if [ -e "$version_dir" ]; then
    [ -d "$version_dir" ] && [ ! -L "$version_dir" ] \
        || die "$version_dir exists but is not a regular directory"
    [ -f "$immutable_binary" ] && [ ! -L "$immutable_binary" ] \
        || die "$immutable_binary is not a regular file"
    [ "$(shasum -a 256 "$immutable_binary" | awk '{print $1}')" = "$expected_binary_sha" ] \
        || die "immutable version directory has different binary bytes"
    codpiece_regular_private_receipt "$version_dir/metadata.json" \
        || die "immutable version directory has no private regular metadata"
    [ "$(shasum -a 256 "$version_dir/metadata.json" | awk '{print $1}')" = \
        "$expected_metadata_sha" ] \
        || die "immutable version directory metadata does not match the local-build receipt"
    codpiece_regular_private_receipt "$version_dir/install.json" \
        || die "immutable version directory has no private regular install receipt"
    jq -e \
        --arg sha "$expected_sha" \
        --arg binary "$immutable_binary" \
        --arg binarySha "$expected_binary_sha" \
        --arg binaryVersion "$expected_binary_version" \
        --arg metadata "$version_dir/metadata.json" \
        --arg metadataSha "$expected_metadata_sha" \
        --arg buildReceipt "$local_receipt" \
        --arg buildReceiptSha "$local_receipt_sha" '
            .schemaVersion == 1 and .integrationSha == $sha and
            .source == "possibilities/codex:integration" and
            .package == "codex-voice-sidecar" and .binary == $binary and
            .binarySha256 == $binarySha and
            .binaryVersion == $binaryVersion and
            .metadata == $metadata and
            .metadataSha256 == $metadataSha and
            .buildReceipt == $buildReceipt and
            .buildReceiptSha256 == $buildReceiptSha and
            (.installedAt | type == "string" and length > 0)
        ' "$version_dir/install.json" >/dev/null \
        || die "immutable version directory has an invalid install receipt"
else
    mkdir "$staging"
    install -m 0755 "$built_binary" "$staging/$package"
    install -m 0600 "$metadata_source" "$staging/metadata.json"
    installed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    jq -n \
        --arg integrationSha "$expected_sha" \
        --arg binary "$immutable_binary" \
        --arg binarySha256 "$expected_binary_sha" \
        --arg binaryVersion "$expected_binary_version" \
        --arg metadata "$version_dir/metadata.json" \
        --arg metadataSha256 "$expected_metadata_sha" \
        --arg buildReceipt "$local_receipt" \
        --arg buildReceiptSha256 "$local_receipt_sha" \
        --arg installedAt "$installed_at" \
        '{schemaVersion:1,integrationSha:$integrationSha,
          source:"possibilities/codex:integration",
          package:"codex-voice-sidecar",binary:$binary,
          binarySha256:$binarySha256,binaryVersion:$binaryVersion,
          metadata:$metadata,metadataSha256:$metadataSha256,
          buildReceipt:$buildReceipt,buildReceiptSha256:$buildReceiptSha256,
          installedAt:$installedAt}' >"$staging/install.json"
    chmod 0600 "$staging/install.json"
    mv "$staging" "$version_dir"
fi

if [ -e "$current_link" ] && [ ! -L "$current_link" ]; then
    die "$current_link exists and is not a symbolic link"
fi
if [ -L "$current_link" ]; then
    old_current_present=1
    old_current_target=$(readlink "$current_link")
fi

expected_binary_link_target="$current_link/$package"
if [ -e "$binary_link" ] && [ ! -L "$binary_link" ]; then
    die "$binary_link exists and is not a symbolic link"
fi
if [ -L "$binary_link" ]; then
    [ "$(readlink "$binary_link")" = "$expected_binary_link_target" ] \
        || die "$binary_link does not point at the Codpiece consumer path"
else
    ln -s "$expected_binary_link_target" "$binary_link_tmp"
    mv "$binary_link_tmp" "$binary_link"
    binary_link_created=1
fi

if [ "$test_mode" -eq 1 ] \
    && [ -n "${CODPIECE_INSTALL_BEFORE_ACTIVATE_HOOK:-}" ]; then
    [ -x "$CODPIECE_INSTALL_BEFORE_ACTIVATE_HOOK" ] \
        || die "installation test hook is not executable"
    "$CODPIECE_INSTALL_BEFORE_ACTIVATE_HOOK" "$actual_fork_url"
fi

# Re-read the only moving remote immediately before the one atomic activation.
published=$(remote_integration)
[ "$published" = "$expected_sha" ] \
    || die "fork/integration moved to $published during installation"
[ -z "$(git -C "$checkout" status --porcelain)" ] \
    || die "$checkout changed during installation"

ln -s "versions/$expected_sha" "$current_tmp"
mv -fh "$current_tmp" "$current_link"
activated=1
if [ "$test_mode" -eq 1 ] \
    && [ "${CODPIECE_INSTALL_FAIL_AFTER_ACTIVATE:-0}" -eq 1 ]; then
    die "injected failure after activation"
fi
reported=$("$binary_link" --version)
[ "$reported" = "$expected_binary_version" ] \
    || die "installed binary reports $reported, expected $expected_binary_version"
[ "$(shasum -a 256 "$binary_link" | awk '{print $1}')" = "$expected_binary_sha" ] \
    || die "installed binary changed during activation"
codpiece_regular_private_receipt "$current_link/metadata.json" \
    || die "installed metadata is not private and reachable through the consumer pointer"
[ "$(shasum -a 256 "$current_link/metadata.json" | awk '{print $1}')" = \
    "$expected_metadata_sha" ] \
    || die "installed metadata changed during activation"
codpiece_regular_private_receipt "$installed_receipt" \
    || die "installed receipt is not private and reachable through the consumer pointer"
[ "$(jq -r '.integrationSha' "$installed_receipt")" = "$expected_sha" ] \
    || die "installed receipt reports the wrong Integration commit"
codpiece_release_lock_release || die "could not release the installation lock"
lock_held=0
binary_link_created=0
activated=0

printf 'codpiece installer: installed %s at %s (%s); receipt %s\n' \
    "$expected_sha" "$binary_link" "$expected_binary_version" "$installed_receipt"
