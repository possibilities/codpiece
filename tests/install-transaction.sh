#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

fail() {
    printf 'codpiece install test: %s\n' "$*" >&2
    exit 1
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/codpiece-install-test.XXXXXX")
cleanup() {
    local status=$?
    trap - EXIT
    rm -rf -- "$scratch"
    exit "$status"
}
trap cleanup EXIT

git_identity=(-c user.name=Codpiece -c user.email=codpiece@example.invalid)

new_fixture() {
    local name=$1
    case_root="$scratch/$name"
    checkout="$case_root/checkout"
    fork="$case_root/fork.git"
    state="$case_root/state"
    target="$case_root/target"
    install_root="$case_root/install"
    binary_link="$case_root/bin/codex-voice-sidecar"
    fake_bin="$case_root/fake-bin"
    fake_binary="$case_root/fake-codex-voice-sidecar"
    metadata_source="$case_root/metadata.json"
    mkdir -p "$checkout/codex-rs" "$fake_bin" "$(dirname "$binary_link")"

    git init --quiet --initial-branch=main "$checkout"
    printf '[workspace]\nmembers = []\n' >"$checkout/codex-rs/Cargo.toml"
    printf 'candidate\n' >"$checkout/candidate.txt"
    git -C "$checkout" add codex-rs/Cargo.toml candidate.txt
    git -C "$checkout" "${git_identity[@]}" commit --quiet -m candidate
    candidate_sha=$(git -C "$checkout" rev-parse HEAD)
    candidate_tree=$(git -C "$checkout" rev-parse 'HEAD^{tree}')

    git init --quiet --bare "$fork"
    git -C "$checkout" remote add fork "$fork"
    git -C "$checkout" push --quiet fork \
        "$candidate_sha:refs/heads/main" \
        "$candidate_sha:refs/heads/integration"

    cat >"$fake_binary" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    printf 'codex-voice-sidecar 0.1.0-test\n'
    exit 0
fi
printf 'test binary accepts only --version\n' >&2
exit 64
EOF
    chmod 0755 "$fake_binary"
    binary_sha=$(shasum -a 256 "$fake_binary" | awk '{print $1}')
    binary_version=$($fake_binary --version)

    cat >"$fake_bin/cargo" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-}" = build ] || {
    printf 'fake cargo expected build\n' >&2
    exit 64
}
[ "$CARGO_TARGET_DIR" = "$CODPIECE_TARGET_DIR/reproductions/$CODPIECE_EXPECTED_SHA" ] || {
    printf 'fake cargo expected reproduction target\n' >&2
    exit 65
}
mkdir -p "$CARGO_TARGET_DIR/release"
install -m 0755 "$CODPIECE_FAKE_BINARY" \
    "$CARGO_TARGET_DIR/release/codex-voice-sidecar"
EOF
    chmod 0755 "$fake_bin/cargo"

    contract_sha=$(codpiece_gate_contract_digest "$root") \
        || fail "could not hash gate contract"
    dependency_sha=7777777777777777777777777777777777777777777777777777777777777777
    mkdir -p "$state/local-builds"
    sidecar_metadata=$(jq -n \
        --arg sha "$candidate_sha" \
        --arg binarySha "$binary_sha" \
        --arg binaryVersion "$binary_version" \
        '{schemaVersion:3,implementation:"codex-voice-sidecar",
          sourceRepository:"possibilities/codex",sourceRevision:$sha,
          upstreamRevision:$sha,builtAt:"2026-08-30T00:00:00Z",
          binarySha256:$binarySha,binaryVersion:$binaryVersion,
          credentialAuthority:{owner:"fx",provider:"codex",
            transport:"inherited-fd",descriptor:3,protocolVersion:1,
            maxFrameBytes:65536}}')
    printf '%s\n' "$sidecar_metadata" >"$metadata_source"
    chmod 0600 "$metadata_source"
    metadata_sha=$(shasum -a 256 "$metadata_source" | awk '{print $1}')
    local_receipt="$state/local-builds/$candidate_sha.json"
    jq -n \
        --arg sha "$candidate_sha" \
        --arg tree "$candidate_tree" \
        --arg contract "$contract_sha" \
        --arg binarySha "$binary_sha" \
        --arg binaryVersion "$binary_version" \
        --arg metadata "$metadata_source" \
        --arg metadataSha "$metadata_sha" \
        --arg dependencySha "$dependency_sha" \
        '{schemaVersion:1,status:"local-pass",candidateSha:$sha,
          candidateTree:$tree,upstream:{ref:"origin/main",sha:$sha},
          gateContractSha256:$contract,
          package:"codex-voice-sidecar",binary:"/tmp/codex-voice-sidecar",
          binarySha256:$binarySha,binaryVersion:$binaryVersion,
          binaryBytes:1,metadata:$metadata,metadataSha256:$metadataSha,
          dependencyCount:1,dependencyGraphSha256:$dependencySha,
          budgetsEnforced:true,
          build:{cargoJobs:2,releaseLto:false,releaseCodegenUnits:1},
          recordedAt:"2026-08-30T00:00:00Z"}' \
        >"$local_receipt"
    chmod 0600 "$local_receipt"
}

install_candidate() {
    PATH="$fake_bin:$PATH" \
    CODPIECE_FAKE_BINARY="$fake_binary" \
    CODPIECE_EXPECTED_SHA="$candidate_sha" \
    CODPIECE_TESTING=1 \
    CODPIECE_CODEX_CHECKOUT="$checkout" \
    CODPIECE_FORK_URL="$fork" \
    CODPIECE_STATE_DIR="$state" \
    CODPIECE_TARGET_DIR="$target" \
    CODPIECE_INSTALL_ROOT="$install_root" \
    CODPIECE_BINARY_LINK="$binary_link" \
        "$root/scripts/install.sh" --install --sha "$candidate_sha"
}

expect_install_failure() {
    local expected=$1
    shift
    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "installation unexpectedly succeeded: $expected"
    printf '%s\n' "$output" | grep -F "$expected" >/dev/null \
        || fail "installation failure did not explain: $expected"
}


assert_clean_runtime() {
    [ ! -e "$state/release.lock" ] \
        || fail "installer left the release lock behind"
    [ "$(git -C "$checkout" worktree list --porcelain \
        | grep -c '^worktree ')" -eq 1 ] \
        || fail "installer left a detached worktree behind"
}

new_fixture success
install_output=$(install_candidate)
printf '%s\n' "$install_output" | grep -F "installed $candidate_sha" >/dev/null \
    || fail "successful install did not name its exact commit"
immutable_binary="$install_root/versions/$candidate_sha/codex-voice-sidecar"
immutable_metadata="$install_root/versions/$candidate_sha/metadata.json"
[ -L "$binary_link" ] || fail "consumer pointer is not a symbolic link"
[ "$(readlink "$binary_link")" = "$install_root/current/codex-voice-sidecar" ] \
    || fail "binary link does not use the sole consumer pointer"
[ "$(readlink "$install_root/current")" = "versions/$candidate_sha" ] \
    || fail "consumer pointer does not name the immutable version"
[ "$($binary_link --version)" = "$binary_version" ] \
    || fail "installed binary reported the wrong version"
[ "$(jq -r '.binary' "$install_root/versions/$candidate_sha/install.json")" = \
    "$immutable_binary" ] || fail "install receipt names a moving path"
[ "$(shasum -a 256 "$immutable_metadata" | awk '{print $1}')" = \
    "$metadata_sha" ] || fail "installed metadata is not local-build exact"
[ "$(jq -r '.metadata' "$install_root/versions/$candidate_sha/install.json")" = \
    "$immutable_metadata" ] || fail "install receipt omits immutable metadata"
[ "$(jq -r '.metadataSha256' "$install_root/versions/$candidate_sha/install.json")" = \
    "$metadata_sha" ] || fail "install receipt metadata hash is not local-build exact"
[ "$(jq -r '.integrationSha' "$install_root/current/install.json")" = \
    "$candidate_sha" ] || fail "stable installed receipt reports the wrong commit"
assert_clean_runtime

new_fixture upgrade
old_version="$install_root/versions/old"
old_binary="$old_version/codex-voice-sidecar"
mkdir -p "$old_version"
cat >"$old_binary" <<'EOF'
#!/bin/sh
printf 'old voice\n'
EOF
chmod 0755 "$old_binary"
printf '{"integrationSha":"old"}\n' >"$old_version/install.json"
ln -s versions/old "$install_root/current"
ln -s "$install_root/current/codex-voice-sidecar" "$binary_link"
install_candidate >/dev/null
[ "$(readlink "$install_root/current")" = "versions/$candidate_sha" ] \
    || fail "successful upgrade did not replace the prior consumer pointer"
[ "$($binary_link --version)" = "$binary_version" ] \
    || fail "successful upgrade did not activate the candidate binary"
[ -z "$(find "$old_version" -maxdepth 1 -name '.current.*' -print -quit)" ] \
    || fail "successful upgrade moved the activation symlink into the prior version"
assert_clean_runtime

new_fixture rollback
old_version="$install_root/versions/old"
old_binary="$old_version/codex-voice-sidecar"
mkdir -p "$old_version"
cat >"$old_binary" <<'EOF'
#!/bin/sh
printf 'old voice\n'
EOF
chmod 0755 "$old_binary"
printf '{"integrationSha":"old"}\n' >"$old_version/install.json"
ln -s versions/old "$install_root/current"
ln -s "$install_root/current/codex-voice-sidecar" "$binary_link"
set +e
rollback_output=$(CODPIECE_INSTALL_FAIL_AFTER_ACTIVATE=1 install_candidate 2>&1)
rollback_status=$?
set -e
[ "$rollback_status" -ne 0 ] || fail "injected post-activation failure succeeded"
printf '%s\n' "$rollback_output" | grep -F 'injected failure after activation' >/dev/null \
    || fail "post-activation failure was not reported"
[ -L "$install_root/current" ] \
    && [ "$(readlink "$install_root/current")" = versions/old ] \
    || fail "post-activation failure did not restore the prior pointer"
[ "$("$binary_link")" = 'old voice' ] \
    || fail "restored binary link does not reach the prior version"
assert_clean_runtime

new_fixture regular-destination
printf 'do not replace\n' >"$binary_link"
set +e
regular_output=$(install_candidate 2>&1)
regular_status=$?
set -e
[ "$regular_status" -ne 0 ] || fail "installer replaced a regular destination"
printf '%s\n' "$regular_output" | grep -F 'exists and is not a symbolic link' >/dev/null \
    || fail "regular destination refusal was not explained"
[ "$(cat "$binary_link")" = 'do not replace' ] \
    || fail "regular destination changed"
assert_clean_runtime

new_fixture invalid-immutable-receipt
invalid_version="$install_root/versions/$candidate_sha"
mkdir -p "$invalid_version"
install -m 0755 "$fake_binary" "$invalid_version/codex-voice-sidecar"
install -m 0600 "$metadata_source" "$invalid_version/metadata.json"
printf '{"schemaVersion":1,"integrationSha":"wrong"}\n' \
    >"$invalid_version/install.json"
chmod 0600 "$invalid_version/metadata.json" "$invalid_version/install.json"
set +e
invalid_receipt_output=$(install_candidate 2>&1)
invalid_receipt_status=$?
set -e
[ "$invalid_receipt_status" -ne 0 ] \
    || fail "installer accepted a malformed immutable install receipt"
printf '%s\n' "$invalid_receipt_output" \
    | grep -F 'invalid install receipt' >/dev/null \
    || fail "malformed immutable receipt refusal was not explained"
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "malformed immutable receipt moved a consumer pointer"
assert_clean_runtime

new_fixture invalid-immutable-metadata
invalid_version="$install_root/versions/$candidate_sha"
mkdir -p "$invalid_version"
install -m 0755 "$fake_binary" "$invalid_version/codex-voice-sidecar"
jq -S '.credentialAuthority.descriptor = 4' \
    "$metadata_source" >"$invalid_version/metadata.json"
tampered_metadata_sha=$(shasum -a 256 "$invalid_version/metadata.json" \
    | awk '{print $1}')

local_receipt_sha=$(shasum -a 256 "$local_receipt" | awk '{print $1}')
jq -n \
    --arg sha "$candidate_sha" \
    --arg binary "$invalid_version/codex-voice-sidecar" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg metadata "$invalid_version/metadata.json" \
    --arg metadataSha "$tampered_metadata_sha" \
    --arg buildReceipt "$local_receipt" \
    --arg buildReceiptSha "$local_receipt_sha" \
    '{schemaVersion:1,integrationSha:$sha,
      source:"possibilities/codex:integration",
      package:"codex-voice-sidecar",binary:$binary,
      binarySha256:$binarySha,binaryVersion:$binaryVersion,
      metadata:$metadata,metadataSha256:$metadataSha,
      buildReceipt:$buildReceipt,buildReceiptSha256:$buildReceiptSha,
      installedAt:"2026-08-30T00:00:00Z"}' \
    >"$invalid_version/install.json"
chmod 0600 "$invalid_version/metadata.json" "$invalid_version/install.json"
expect_install_failure 'metadata does not match the local-build receipt' install_candidate
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "tampered immutable metadata moved a consumer pointer"
assert_clean_runtime

new_fixture shallow-build-receipt
jq -n \
    --arg sha "$candidate_sha" \
    --arg contract "$contract_sha" \
    '{schemaVersion:1,status:"local-pass",candidateSha:$sha,
      gateContractSha256:$contract,budgetsEnforced:true}' \
    >"$local_receipt"
chmod 0600 "$local_receipt"
expect_install_failure 'local-build receipt does not prove' install_candidate
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "shallow build receipt moved a consumer pointer"
assert_clean_runtime

new_fixture mismatched-local-binary
jq '.binarySha256 =
    "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"' \
    "$local_receipt" >"$local_receipt.tmp"
mv "$local_receipt.tmp" "$local_receipt"
chmod 0600 "$local_receipt"
expect_install_failure 'sidecar metadata does not describe this candidate' install_candidate
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "mismatched local binary receipt moved a consumer pointer"
assert_clean_runtime

new_fixture mismatched-local-metadata-object
jq '.binaryVersion = "codex-voice-sidecar 0.1.0-tampered"' \
    "$metadata_source" >"$metadata_source.tmp"
mv "$metadata_source.tmp" "$metadata_source"
chmod 0600 "$metadata_source"
metadata_sha=$(shasum -a 256 "$metadata_source" | awk '{print $1}')
jq --arg metadataSha "$metadata_sha" \
    '.metadataSha256 = $metadataSha' \
    "$local_receipt" >"$local_receipt.tmp"
mv "$local_receipt.tmp" "$local_receipt"
chmod 0600 "$local_receipt"
expect_install_failure 'sidecar metadata does not describe this candidate' \
    install_candidate
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "mismatched local metadata moved a consumer pointer"
assert_clean_runtime

new_fixture production-remote-override
set +e
production_remote_output=$(
    PATH="$fake_bin:$PATH" \
    CODPIECE_FAKE_BINARY="$fake_binary" \
    CODPIECE_EXPECTED_SHA="$candidate_sha" \
    CODPIECE_TESTING=0 \
    CODPIECE_CODEX_CHECKOUT="$checkout" \
    CODPIECE_FORK_URL="$fork" \
    CODPIECE_STATE_DIR="$state" \
    CODPIECE_TARGET_DIR="$target" \
    CODPIECE_INSTALL_ROOT="$install_root" \
    CODPIECE_BINARY_LINK="$binary_link" \
        "$root/scripts/install.sh" --install --sha "$candidate_sha" 2>&1
)
production_remote_status=$?
set -e
[ "$production_remote_status" -ne 0 ] \
    || fail "installer accepted a production local-remote override"
printf '%s\n' "$production_remote_output" \
    | grep -F 'not https://github.com/possibilities/codex.git' >/dev/null \
    || fail "production remote override refusal was not explained"
assert_clean_runtime

new_fixture missing-local-metadata
rm -f -- "$metadata_source"
expect_install_failure 'local-build metadata is not a private regular file' install_candidate
[ ! -e "$install_root/current" ] && [ ! -e "$binary_link" ] \
    || fail "missing local metadata moved a consumer pointer"
assert_clean_runtime

new_fixture leaked-test-remote
git -C "$checkout" remote set-url fork git@github.com:possibilities/codex.git
expect_install_failure 'test mode refuses non-local fork remote' install_candidate
assert_clean_runtime

new_fixture locked
mkdir -p "$state/release.lock"
printf 'someone-else\n' >"$state/release.lock/pid"
set +e
locked_output=$(install_candidate 2>&1)
locked_status=$?
set -e
[ "$locked_status" -ne 0 ] || fail "installer ignored the release lock"
printf '%s\n' "$locked_output" | grep -F 'release lock is busy' >/dev/null \
    || fail "release-lock refusal was not explained"
[ -f "$state/release.lock/pid" ] \
    || fail "installer removed another owner's lock"
rm -f -- "$state/release.lock/pid"
rmdir "$state/release.lock"

new_fixture remote-move
old_version="$install_root/versions/old"
old_binary="$old_version/codex-voice-sidecar"
mkdir -p "$old_version"
cat >"$old_binary" <<'EOF'
#!/bin/sh
printf 'old voice\n'
EOF
chmod 0755 "$old_binary"
printf '{"integrationSha":"old"}\n' >"$old_version/install.json"
ln -s versions/old "$install_root/current"
ln -s "$install_root/current/codex-voice-sidecar" "$binary_link"
printf 'race\n' >"$checkout/race.txt"
git -C "$checkout" add race.txt
git -C "$checkout" "${git_identity[@]}" commit --quiet -m race
race_sha=$(git -C "$checkout" rev-parse HEAD)
git -C "$checkout" push --quiet fork "$race_sha:refs/heads/race-object"
move_hook="$case_root/move-integration.sh"
cat >"$move_hook" <<EOF
#!/bin/bash
set -euo pipefail
git --git-dir="\$1" update-ref refs/heads/integration "$race_sha"
EOF
chmod 0755 "$move_hook"
set +e
move_output=$(
    CODPIECE_INSTALL_BEFORE_ACTIVATE_HOOK="$move_hook" \
        install_candidate 2>&1
)
move_status=$?
set -e
[ "$move_status" -ne 0 ] || fail "installer ignored a final remote move"
printf '%s\n' "$move_output" | grep -F "fork/integration moved to $race_sha" >/dev/null \
    || fail "final remote move refusal was not explained"
[ -L "$install_root/current" ] \
    && [ "$(readlink "$install_root/current")" = versions/old ] \
    || fail "remote move changed the consumer pointer"
assert_clean_runtime

printf 'codpiece installer transaction tests passed.\n'
