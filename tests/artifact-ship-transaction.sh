#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

fail() {
    printf 'codpiece artifact/ship test: %s\n' "$*" >&2
    exit 1
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/codpiece-artifact-ship-test.XXXXXX")
cleanup() {
    local status=$?
    trap - EXIT
    rm -rf -- "$scratch"
    exit "$status"
}
trap cleanup EXIT

checkout="$scratch/checkout"
upstream="$scratch/upstream.git"
fork="$scratch/fork.git"
state="$scratch/state"
agentvoice="$scratch/agentvoice"
artifact="$scratch/artifact"
fake_bin="$scratch/fake-bin"
binary="$scratch/codex-voice-sidecar"
metadata="$scratch/metadata.json"
mkdir -p "$checkout" "$agentvoice/src" "$artifact" "$fake_bin"

git_identity=(-c user.name=Codpiece -c user.email=codpiece@example.invalid)
git init --quiet --initial-branch=main "$checkout"
printf 'upstream\n' >"$checkout/upstream.txt"
git -C "$checkout" add upstream.txt
git -C "$checkout" "${git_identity[@]}" commit --quiet -m upstream
upstream_sha=$(git -C "$checkout" rev-parse HEAD)
git init --quiet --bare "$upstream"
git init --quiet --bare "$fork"
git -C "$checkout" remote add origin "$upstream"
git -C "$checkout" remote add fork "$fork"
git -C "$checkout" push --quiet origin main
git -C "$checkout" push --quiet fork main
git -C "$checkout" switch --quiet -c carry/voice-sidecar
printf 'voice\n' >"$checkout/voice.txt"
git -C "$checkout" add voice.txt
git -C "$checkout" "${git_identity[@]}" commit --quiet -m voice
candidate_sha=$(git -C "$checkout" rev-parse HEAD)
candidate_tree=$(git -C "$checkout" rev-parse 'HEAD^{tree}')

cat >"$binary" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    printf 'codex-voice-sidecar 0.1.0-test\n'
    exit 0
fi
printf 'test binary accepts only --version\n' >&2
exit 64
EOF
chmod 0755 "$binary"
binary_version=$($binary --version)
binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')
wire_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
jq -n \
    --arg sha "$candidate_sha" \
    --arg upstream "$upstream_sha" \
    --arg wire "$wire_sha" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" '
        {schemaVersion:2,implementation:"codex-voice-sidecar",
         sourceRepository:"possibilities/codex",sourceRevision:$sha,
         upstreamRevision:$upstream,wireContractVersion:1,
         wireContractSha256:$wire,builtAt:"2026-08-30T00:00:00Z",
         binarySha256:$binarySha,binaryVersion:$binaryVersion}
    ' >"$metadata"
chmod 0600 "$metadata"
metadata_sha=$(shasum -a 256 "$metadata" | awk '{print $1}')

git init --quiet --initial-branch=main "$agentvoice"
printf 'validator fixture\n' >"$agentvoice/src/codpiece-artifact-validator-cli.ts"
printf '{"name":"agentvoice-fixture"}\n' >"$agentvoice/package.json"
printf 'bun lock fixture\n' >"$agentvoice/bun.lock"
printf '{"compilerOptions":{}}\n' >"$agentvoice/tsconfig.json"
git -C "$agentvoice" add package.json bun.lock tsconfig.json \
    src/codpiece-artifact-validator-cli.ts
git -C "$agentvoice" "${git_identity[@]}" commit --quiet -m agentvoice
agentvoice_commit=$(git -C "$agentvoice" rev-parse HEAD)
agentvoice_provenance=$(codpiece_agentvoice_provenance "$agentvoice" \
    "$agentvoice/src/codpiece-artifact-validator-cli.ts") \
    || fail "could not bind test AgentVoice provenance"

cat >"$fake_bin/bun" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-}" = run ] || exit 64
shift 2
artifact=
binary=
candidate=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifact) artifact=$2; shift 2 ;;
        --binary) binary=$2; shift 2 ;;
        --candidate-sha) candidate=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
[ -n "$artifact" ] && [ -n "$binary" ] && [ -n "$candidate" ] || exit 64
artifact=$(cd "$artifact" && pwd -P)
binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')
binary_version=$($binary --version)
comparison=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
if [ "${CODPIECE_FAKE_VALIDATOR_VARIANT:-0}" -eq 1 ]; then
    comparison=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
fi
jq -n \
    --arg sha "$candidate" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg wire "$CODPIECE_FAKE_WIRE_SHA" \
    --arg artifact "$artifact" \
    --arg comparison "$comparison" '
        {schemaVersion:1,status:"accepted",candidateSha:$sha,
         binarySha256:$binarySha,binaryVersion:$binaryVersion,
         wireContractSha256:$wire,
         artifact:{path:$artifact,
           manifestSha256:"1111111111111111111111111111111111111111111111111111111111111111",
           eventsSha256:"2222222222222222222222222222222222222222222222222222222222222222",
           scenarioSha256:"3333333333333333333333333333333333333333333333333333333333333333",
           evaluationInputReceiptSha256:"4444444444444444444444444444444444444444444444444444444444444444",
           comparisonWavSha256:$comparison,
           inputWavSha256:"5555555555555555555555555555555555555555555555555555555555555555",
           outputWavSha256:"6666666666666666666666666666666666666666666666666666666666666666",
           declaredEvidenceSha256:{
             events:"2222222222222222222222222222222222222222222222222222222222222222",
             scenario:"3333333333333333333333333333333333333333333333333333333333333333",
             evaluationInputReceipt:"4444444444444444444444444444444444444444444444444444444444444444",
             comparisonAudio:$comparison,
             inputAudio:"5555555555555555555555555555555555555555555555555555555555555555",
             outputAudio:"6666666666666666666666666666666666666666666666666666666666666666"}}}
    '
EOF
chmod 0755 "$fake_bin/bun"

contract_sha=$(codpiece_gate_contract_digest "$root") \
    || fail "could not hash gate contract"
mkdir -p "$state/local-builds"
jq -n \
    --arg sha "$candidate_sha" \
    --arg tree "$candidate_tree" \
    --arg upstream "$upstream_sha" \
    --arg contract "$contract_sha" \
    --arg wire "$wire_sha" \
    --arg binary "$binary" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg metadata "$metadata" \
    --arg metadataSha "$metadata_sha" \
    --argjson agentVoiceProvenance "$agentvoice_provenance" '
        {schemaVersion:1,status:"local-pass",candidateSha:$sha,
         candidateTree:$tree,upstream:{ref:"origin/main",sha:$upstream},
         gateContractSha256:$contract,wireContract:{version:1,sha256:$wire},
         package:"codex-voice-sidecar",binary:$binary,
         binarySha256:$binarySha,binaryVersion:$binaryVersion,
         metadata:$metadata,metadataSha256:$metadataSha,
         dependencyGraphSha256:"7777777777777777777777777777777777777777777777777777777777777777",
         agentVoiceProvenance:$agentVoiceProvenance,
         budgetsEnforced:true}
    ' >"$state/local-builds/$candidate_sha.json"
chmod 0600 "$state/local-builds/$candidate_sha.json"

artifact_gate() {
    PATH="$fake_bin:$PATH" \
    CODPIECE_STATE_DIR="$state" \
    CODPIECE_AGENTVOICE_ROOT="$agentvoice" \
    CODPIECE_FAKE_WIRE_SHA="$wire_sha" \
        "$root/scripts/artifact-gate.sh" \
            --worktree "$checkout" --sha "$candidate_sha" --artifact "$artifact"
}

ship_gate() {
    PATH="$fake_bin:$PATH" \
    CODPIECE_TESTING=1 \
    CODPIECE_STATE_DIR="$state" \
    CODPIECE_AGENTVOICE_ROOT="$agentvoice" \
    CODPIECE_FAKE_WIRE_SHA="$wire_sha" \
    CODPIECE_FAKE_VALIDATOR_VARIANT="${CODPIECE_FAKE_VALIDATOR_VARIANT:-0}" \
        "$root/scripts/ship-gate.sh" --worktree "$checkout" --sha "$candidate_sha"
}

expect_failure() {
    local expected=$1
    shift
    local output status
    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "command unexpectedly succeeded: $expected"
    printf '%s\n' "$output" | grep -F "$expected" >/dev/null \
        || fail "failure did not explain: $expected"
}

new_fixture() {
    local case_name=$1 case_root

    case_root="$scratch/$case_name"
    checkout="$case_root/checkout"
    upstream="$case_root/upstream.git"
    fork="$case_root/fork.git"
    state="$case_root/state"
    agentvoice="$case_root/agentvoice"
    artifact="$case_root/artifact"
    fake_bin="$case_root/fake-bin"
    binary="$case_root/codex-voice-sidecar"
    metadata="$case_root/metadata.json"
    mkdir -p "$checkout" "$agentvoice/src" "$artifact" "$fake_bin"

    git init --quiet --initial-branch=main "$checkout"
    printf 'upstream\n' >"$checkout/upstream.txt"
    git -C "$checkout" add upstream.txt
    git -C "$checkout" "${git_identity[@]}" commit --quiet -m upstream
    upstream_sha=$(git -C "$checkout" rev-parse HEAD)
    git init --quiet --bare "$upstream"
    git init --quiet --bare "$fork"
    git -C "$checkout" remote add origin "$upstream"
    git -C "$checkout" remote add fork "$fork"
    git -C "$checkout" push --quiet origin main
    git -C "$checkout" push --quiet fork main
    git -C "$checkout" switch --quiet -c carry/voice-sidecar
    printf 'voice\n' >"$checkout/voice.txt"
    git -C "$checkout" add voice.txt
    git -C "$checkout" "${git_identity[@]}" commit --quiet -m voice
    candidate_sha=$(git -C "$checkout" rev-parse HEAD)
    candidate_tree=$(git -C "$checkout" rev-parse 'HEAD^{tree}')

    cat >"$binary" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    printf 'codex-voice-sidecar 0.1.0-test\n'
    exit 0
fi
printf 'test binary accepts only --version\n' >&2
exit 64
EOF
    chmod 0755 "$binary"
    binary_version=$($binary --version)
    binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')
    wire_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    jq -n \
        --arg sha "$candidate_sha" \
        --arg upstream "$upstream_sha" \
        --arg wire "$wire_sha" \
        --arg binarySha "$binary_sha" \
        --arg binaryVersion "$binary_version" '
            {schemaVersion:2,implementation:"codex-voice-sidecar",
             sourceRepository:"possibilities/codex",sourceRevision:$sha,
             upstreamRevision:$upstream,wireContractVersion:1,
             wireContractSha256:$wire,builtAt:"2026-08-30T00:00:00Z",
             binarySha256:$binarySha,binaryVersion:$binaryVersion}
        ' >"$metadata"
    chmod 0600 "$metadata"
    metadata_sha=$(shasum -a 256 "$metadata" | awk '{print $1}')

    git init --quiet --initial-branch=main "$agentvoice"
    printf 'validator fixture\n' >"$agentvoice/src/codpiece-artifact-validator-cli.ts"
    printf '{"name":"agentvoice-fixture"}\n' >"$agentvoice/package.json"
    printf 'bun lock fixture\n' >"$agentvoice/bun.lock"
    printf '{"compilerOptions":{}}\n' >"$agentvoice/tsconfig.json"
    git -C "$agentvoice" add package.json bun.lock tsconfig.json \
        src/codpiece-artifact-validator-cli.ts
    git -C "$agentvoice" "${git_identity[@]}" commit --quiet -m agentvoice
    agentvoice_commit=$(git -C "$agentvoice" rev-parse HEAD)
    agentvoice_provenance=$(codpiece_agentvoice_provenance "$agentvoice" \
        "$agentvoice/src/codpiece-artifact-validator-cli.ts") \
        || fail "could not bind test AgentVoice provenance"

    cat >"$fake_bin/bun" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-}" = run ] || exit 64
shift 2
artifact=
binary=
candidate=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifact) artifact=$2; shift 2 ;;
        --binary) binary=$2; shift 2 ;;
        --candidate-sha) candidate=$2; shift 2 ;;
        *) exit 64 ;;
    esac
done
[ -n "$artifact" ] && [ -n "$binary" ] && [ -n "$candidate" ] || exit 64
artifact=$(cd "$artifact" && pwd -P)
binary_sha=$(shasum -a 256 "$binary" | awk '{print $1}')
binary_version=$($binary --version)
comparison=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
if [ "${CODPIECE_FAKE_VALIDATOR_VARIANT:-0}" -eq 1 ]; then
    comparison=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
fi
jq -n \
    --arg sha "$candidate" \
    --arg binarySha "$binary_sha" \
    --arg binaryVersion "$binary_version" \
    --arg wire "$CODPIECE_FAKE_WIRE_SHA" \
    --arg artifact "$artifact" \
    --arg comparison "$comparison" '
        {schemaVersion:1,status:"accepted",candidateSha:$sha,
         binarySha256:$binarySha,binaryVersion:$binaryVersion,
         wireContractSha256:$wire,
         artifact:{path:$artifact,
           manifestSha256:"1111111111111111111111111111111111111111111111111111111111111111",
           eventsSha256:"2222222222222222222222222222222222222222222222222222222222222222",
           scenarioSha256:"3333333333333333333333333333333333333333333333333333333333333333",
           evaluationInputReceiptSha256:"4444444444444444444444444444444444444444444444444444444444444444",
           comparisonWavSha256:$comparison,
           inputWavSha256:"5555555555555555555555555555555555555555555555555555555555555555",
           outputWavSha256:"6666666666666666666666666666666666666666666666666666666666666666",
           declaredEvidenceSha256:{
             events:"2222222222222222222222222222222222222222222222222222222222222222",
             scenario:"3333333333333333333333333333333333333333333333333333333333333333",
             evaluationInputReceipt:"4444444444444444444444444444444444444444444444444444444444444444",
             comparisonAudio:$comparison,
             inputAudio:"5555555555555555555555555555555555555555555555555555555555555555",
             outputAudio:"6666666666666666666666666666666666666666666666666666666666666666"}}}
    '
EOF
    chmod 0755 "$fake_bin/bun"

    contract_sha=$(codpiece_gate_contract_digest "$root") \
        || fail "could not hash gate contract"
    mkdir -p "$state/local-builds"
    jq -n \
        --arg sha "$candidate_sha" \
        --arg tree "$candidate_tree" \
        --arg upstream "$upstream_sha" \
        --arg contract "$contract_sha" \
        --arg wire "$wire_sha" \
        --arg binary "$binary" \
        --arg binarySha "$binary_sha" \
        --arg binaryVersion "$binary_version" \
        --arg metadata "$metadata" \
        --arg metadataSha "$metadata_sha" \
        --argjson agentVoiceProvenance "$agentvoice_provenance" '
            {schemaVersion:1,status:"local-pass",candidateSha:$sha,
             candidateTree:$tree,upstream:{ref:"origin/main",sha:$upstream},
             gateContractSha256:$contract,wireContract:{version:1,sha256:$wire},
             package:"codex-voice-sidecar",binary:$binary,
             binarySha256:$binarySha,binaryVersion:$binaryVersion,
             metadata:$metadata,metadataSha256:$metadataSha,
             dependencyGraphSha256:"7777777777777777777777777777777777777777777777777777777777777777",
             agentVoiceProvenance:$agentVoiceProvenance,
             budgetsEnforced:true}
        ' >"$state/local-builds/$candidate_sha.json"
    chmod 0600 "$state/local-builds/$candidate_sha.json"
}

mv "$agentvoice/src/codpiece-artifact-validator-cli.ts" \
    "$agentvoice/src/codpiece-artifact-validator-cli.ts.away"
expect_failure 'AgentVoice native validator is missing' artifact_gate
mv "$agentvoice/src/codpiece-artifact-validator-cli.ts.away" \
    "$agentvoice/src/codpiece-artifact-validator-cli.ts"

printf 'committed validator drift\n' \
    >>"$agentvoice/src/codpiece-artifact-validator-cli.ts"
git -C "$agentvoice" add src/codpiece-artifact-validator-cli.ts
git -C "$agentvoice" "${git_identity[@]}" commit --quiet -m validator-drift
expect_failure 'current AgentVoice provenance does not match the local-build receipt' \
    artifact_gate
git -C "$agentvoice" reset --quiet --hard "$agentvoice_commit"

artifact_gate >/dev/null
artifact_receipt="$state/artifact-gates/$candidate_sha.json"
codpiece_regular_private_receipt "$artifact_receipt" \
    || fail "artifact gate did not create a private regular receipt"
jq -e \
    --arg sha "$candidate_sha" \
    '.status == "artifact-pass" and .candidateSha == $sha and
     .agentVoice.status == "accepted" and
     .agentVoiceProvenance.commitSha != null' "$artifact_receipt" >/dev/null \
    || fail "artifact receipt did not bind the accepted validator result"
[ ! -e "$state/release.lock" ] || fail "artifact gate left its release lock"

cp "$binary" "$scratch/original-binary"
printf 'mutation\n' >>"$binary"
expect_failure 'gated binary changed after the local build' artifact_gate
cp "$scratch/original-binary" "$binary"
chmod 0755 "$binary"

new_fixture production-remote-override
set +e
production_remote_output=$(
    PATH="$fake_bin:$PATH" \
    CODPIECE_TESTING=0 \
    CODPIECE_STATE_DIR="$state" \
    CODPIECE_AGENTVOICE_ROOT="$agentvoice" \
    CODPIECE_FORK_URL="$fork" \
        "$root/scripts/ship-gate.sh" --worktree "$checkout" --sha "$candidate_sha" \
        2>&1
)
production_remote_status=$?
set -e
[ "$production_remote_status" -ne 0 ] \
    || fail "ship gate accepted a production local-remote override"
printf '%s\n' "$production_remote_output" \
    | grep -F 'fork remote points at' >/dev/null \
    || fail "production remote override refusal was not explained"

new_fixture stale-origin-main
artifact_gate >/dev/null
git -C "$checkout" push --quiet fork \
    "$candidate_sha:refs/heads/integration"
new_upstream_tree=$(git -C "$checkout" mktree </dev/null)
new_upstream_sha=$(printf 'new upstream\n' \
    | git -C "$checkout" "${git_identity[@]}" commit-tree "$new_upstream_tree" \
        -p "$upstream_sha")
git -C "$checkout" push --quiet origin "$new_upstream_sha:refs/heads/main"
git -C "$checkout" update-ref refs/remotes/origin/main "$upstream_sha"
expect_failure 'local build covered a different origin/main commit' ship_gate

new_fixture ship-path
artifact_gate >/dev/null
git -C "$checkout" push --quiet fork \
    "$candidate_sha:refs/heads/integration"
git -C "$checkout" remote set-url fork https://github.com/possibilities/codex.git
expect_failure 'test mode refuses non-local fork remote' ship_gate
git -C "$checkout" remote set-url fork "$fork"

printf 'ship validator drift\n' \
    >>"$agentvoice/src/codpiece-artifact-validator-cli.ts"
git -C "$agentvoice" add src/codpiece-artifact-validator-cli.ts
git -C "$agentvoice" "${git_identity[@]}" commit --quiet -m ship-validator-drift
expect_failure 'current AgentVoice provenance does not match the artifact-gate receipt' \
    ship_gate
git -C "$agentvoice" reset --quiet --hard "$agentvoice_commit"

CODPIECE_FAKE_VALIDATOR_VARIANT=1 \
    expect_failure 'validation no longer matches' ship_gate
ship_gate >/dev/null
ship_receipt="$state/ship-gates/$candidate_sha.json"
codpiece_regular_private_receipt "$ship_receipt" \
    || fail "ship gate did not create a private regular receipt"
jq -e \
    --arg sha "$candidate_sha" \
    --arg binarySha "$binary_sha" '
        .status == "ship" and .candidateSha == $sha and
        .binarySha256 == $binarySha and .agentVoice.status == "accepted"
    ' "$ship_receipt" >/dev/null \
    || fail "ship receipt did not bind the published candidate"
jq -e --arg metadataSha "$metadata_sha" \
    '.metadataSha256 == $metadataSha' "$ship_receipt" >/dev/null \
    || fail "ship receipt did not bind the exact local metadata hash"
ship_gate >/dev/null
[ ! -e "$state/release.lock" ] || fail "ship gate left its release lock"

printf 'codpiece artifact/ship transaction tests passed.\n'
