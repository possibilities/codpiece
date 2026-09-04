#!/bin/bash

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

fail() {
    printf 'codpiece bootstrap test: %s\n' "$*" >&2
    exit 1
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/codpiece-bootstrap-test.XXXXXX")
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
    seed="$case_root/seed"
    upstream="$case_root/upstream.git"
    fork="$case_root/fork.git"
    checkout="$case_root/checkout"
    state="$case_root/state"
    mkdir -p "$case_root"

    git init --quiet --initial-branch=main "$seed"
    printf 'base\n' >"$seed/base.txt"
    git -C "$seed" add base.txt
    git -C "$seed" "${git_identity[@]}" commit --quiet -m base
    base_sha=$(git -C "$seed" rev-parse HEAD)

    git init --quiet --bare "$upstream"
    git init --quiet --bare "$fork"
    git -C "$seed" remote add upstream "$upstream"
    git -C "$seed" remote add fork "$fork"
    git -C "$seed" push --quiet upstream main
    git -C "$seed" push --quiet fork main
    git -C "$seed" push --quiet fork "$base_sha:refs/heads/unrelated"

    printf 'upstream\n' >"$seed/upstream.txt"
    git -C "$seed" add upstream.txt
    git -C "$seed" "${git_identity[@]}" commit --quiet -m upstream
    upstream_sha=$(git -C "$seed" rev-parse HEAD)
    git -C "$seed" push --quiet upstream main

    git clone --quiet --origin upstream "$upstream" "$checkout"
    git -C "$checkout" remote add fork "$fork"
    git -C "$checkout" switch --quiet -c carry/voice-sidecar
    printf 'voice\n' >"$checkout/voice.txt"
    git -C "$checkout" add voice.txt
    git -C "$checkout" "${git_identity[@]}" commit --quiet -m voice
    voice_sha=$(git -C "$checkout" rev-parse HEAD)
    git -C "$checkout" switch --quiet -c carry/fx-authorization
    printf 'authorization\n' >"$checkout/authorization.txt"
    git -C "$checkout" add authorization.txt
    git -C "$checkout" "${git_identity[@]}" commit --quiet -m authorization
    integration_sha=$(git -C "$checkout" rev-parse HEAD)
    integration_tree=$(git -C "$checkout" rev-parse 'HEAD^{tree}')
    git -C "$checkout" switch --quiet main

    mkdir -p "$state/local-builds"
    contract_sha=$(codpiece_gate_contract_digest "$root") \
        || fail "could not hash gate contract"
    binary_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    metadata_sha=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    dependency_sha=7777777777777777777777777777777777777777777777777777777777777777
    local_receipt="$state/local-builds/$integration_sha.json"
    jq -n \
        --arg sha "$integration_sha" \
        --arg tree "$integration_tree" \
        --arg upstream "$upstream_sha" \
        --arg contract "$contract_sha" \
        --arg binarySha "$binary_sha" \
        --arg metadataSha "$metadata_sha" \
        --arg dependencySha "$dependency_sha" \
        '{schemaVersion:1,status:"local-pass",candidateSha:$sha,
          candidateTree:$tree,upstream:{ref:"upstream/main",sha:$upstream},
          gateContractSha256:$contract,
          package:"codex-voice-sidecar",binary:"/tmp/codex-voice-sidecar",
          binarySha256:$binarySha,binaryVersion:"codex-voice-sidecar 0.1.0-test",
          binaryBytes:1,metadata:"/tmp/metadata.json",metadataSha256:$metadataSha,
          dependencyCount:1,dependencyGraphSha256:$dependencySha,
          budgetsEnforced:true,
          build:{cargoJobs:2,releaseLto:false,releaseCodegenUnits:1},
          recordedAt:"2026-08-30T00:00:00Z"}' \
        >"$local_receipt"
    chmod 0600 "$local_receipt"
}

bootstrap() {
    CODPIECE_TESTING=1 \
    CODPIECE_CODEX_CHECKOUT="$checkout" \
    CODPIECE_FORK_URL="$fork" \
    CODPIECE_UPSTREAM_URL="$upstream" \
    CODPIECE_STATE_DIR="$state" \
        "$root/scripts/bootstrap-branches.sh" "$@"
}

expect_bootstrap_failure() {
    local expected=$1
    shift
    local output status
    set +e
    output=$(bootstrap "$@" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "bootstrap unexpectedly succeeded: $expected"
    printf '%s\n' "$output" | grep -F "$expected" >/dev/null \
        || fail "bootstrap failure did not explain: $expected"
    [ ! -e "$state/release.lock" ] || fail "failed bootstrap left the release lock"
}

remote_sha() {
    git --git-dir="$fork" rev-parse "$1"
}

remote_missing() {
    ! git --git-dir="$fork" rev-parse --verify --quiet "$1" >/dev/null
}

assert_unmodified_targets() {
    [ "$(remote_sha refs/heads/main)" = "$base_sha" ] \
        || fail "failed transaction moved fork main"
    remote_missing refs/heads/integration \
        || fail "failed transaction created Integration"
    remote_missing refs/heads/carry/voice-sidecar \
        || fail "failed transaction created the carry"
    [ "$(remote_sha refs/heads/unrelated)" = "$base_sha" ] \
        || fail "failed transaction moved an unrelated head"
}

new_fixture happy
check_output=$(bootstrap --check)
printf '%s\n' "$check_output" | grep -F "CREATE carry/voice-sidecar $voice_sha" >/dev/null \
    || fail "check mode omitted the carry plan"
printf '%s\n' "$check_output" | grep -F "CREATE carry/fx-authorization $integration_sha" \
    >/dev/null || fail "check mode omitted the authorization carry plan"
printf '%s\n' "$check_output" | grep -F "CREATE integration $integration_sha" >/dev/null \
    || fail "check mode omitted the Integration plan"
assert_unmodified_targets
bootstrap --apply >/dev/null
[ "$(remote_sha refs/heads/main)" = "$upstream_sha" ] \
    || fail "bootstrap did not mirror upstream Main"
[ "$(remote_sha refs/heads/carry/voice-sidecar)" = "$voice_sha" ] \
    || fail "bootstrap did not publish the voice carry"
[ "$(remote_sha refs/heads/integration)" = "$integration_sha" ] \
    || fail "bootstrap did not publish Integration"
[ "$(remote_sha refs/heads/unrelated)" = "$base_sha" ] \
    || fail "bootstrap moved an unrelated head"
[ "$(git -C "$checkout" rev-parse refs/heads/integration)" = "$integration_sha" ] \
    || fail "bootstrap did not bind local Integration"
[ ! -e "$state/release.lock" ] || fail "bootstrap left its release lock"
repair_output=$(bootstrap --apply)
printf '%s\n' "$repair_output" | grep -F "REPAIRED-LOCAL $integration_sha" >/dev/null \
    || fail "completed bootstrap was not idempotently repairable"
CODPIECE_TESTING=1 \
CODPIECE_CODEX_CHECKOUT="$checkout" \
CODPIECE_STATE_DIR="$state" \
MAINTAIN_UPSTREAM_SHA="$upstream_sha" \
    "$root/scripts/reconcile-branches.sh" --check >/dev/null \
    || fail "normal reconciliation did not accept the bootstrapped topology"

new_fixture interrupted-local-bind
after_push_hook="$case_root/interrupt-after-push.sh"
cat >"$after_push_hook" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$after_push_hook"
set +e
interrupted_output=$(
    CODPIECE_BOOTSTRAP_AFTER_PUSH_HOOK="$after_push_hook" \
        bootstrap --apply 2>&1
)
interrupted_status=$?
set -e
[ "$interrupted_status" -ne 0 ] \
    || fail "post-push interruption unexpectedly succeeded"
printf '%s\n' "$interrupted_output" \
    | grep -F 'remote bootstrap published; local binding was interrupted' >/dev/null \
    || fail "post-push interruption was not explained"
[ "$(remote_sha refs/heads/main)" = "$upstream_sha" ] \
    && [ "$(remote_sha refs/heads/integration)" = "$integration_sha" ] \
    && [ "$(remote_sha refs/heads/carry/voice-sidecar)" = "$voice_sha" ] \
    || fail "post-push interruption lost the remote transaction"
remote_repair_output=$(bootstrap --apply)
printf '%s\n' "$remote_repair_output" | grep -F "REPAIRED-LOCAL $integration_sha" >/dev/null \
    || fail "bootstrap did not repair interrupted local binding"
[ "$(git -C "$checkout" rev-parse refs/heads/integration)" = "$integration_sha" ] \
    || fail "local repair did not create Integration"

race_hook="$scratch/race-hook.sh"
cat >"$race_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
git --git-dir="$1" update-ref "refs/heads/$RACE_REF" "$RACE_SHA"
EOF
chmod 0755 "$race_hook"

for raced_ref in main integration carry/voice-sidecar; do
    new_fixture "race-${raced_ref//\//-}"
    if [ "$raced_ref" = main ]; then
        printf 'racing main\n' >"$seed/race.txt"
        git -C "$seed" add race.txt
        git -C "$seed" "${git_identity[@]}" commit --quiet -m race-main
        race_sha=$(git -C "$seed" rev-parse HEAD)
        git -C "$seed" push --quiet fork "$race_sha:refs/heads/race-object"
    else
        race_sha=$base_sha
    fi
    set +e
    race_output=$(
        RACE_REF="$raced_ref" \
        RACE_SHA="$race_sha" \
        CODPIECE_BOOTSTRAP_BEFORE_PUSH_HOOK="$race_hook" \
            bootstrap --apply 2>&1
    )
    race_status=$?
    set -e
    [ "$race_status" -ne 0 ] \
        || fail "bootstrap accepted a $raced_ref lease race"
    printf '%s\n' "$race_output" | grep -F 'atomic bootstrap push failed' >/dev/null \
        || fail "$raced_ref lease race did not fail at the atomic push"
    case "$raced_ref" in
        main)
            [ "$(remote_sha refs/heads/main)" = "$race_sha" ] \
                || fail "main race did not leave the racing value"
            remote_missing refs/heads/integration \
                || fail "main race partially created Integration"
            remote_missing refs/heads/carry/voice-sidecar \
                || fail "main race partially created the carry"
            ;;
        integration)
            [ "$(remote_sha refs/heads/integration)" = "$race_sha" ] \
                || fail "Integration race did not leave the racing value"
            [ "$(remote_sha refs/heads/main)" = "$base_sha" ] \
                || fail "Integration race partially moved Main"
            remote_missing refs/heads/carry/voice-sidecar \
                || fail "Integration race partially created the carry"
            ;;
        carry/voice-sidecar)
            [ "$(remote_sha refs/heads/carry/voice-sidecar)" = "$race_sha" ] \
                || fail "carry race did not leave the racing value"
            [ "$(remote_sha refs/heads/main)" = "$base_sha" ] \
                || fail "carry race partially moved Main"
            remote_missing refs/heads/integration \
                || fail "carry race partially created Integration"
            ;;
    esac
    [ "$(remote_sha refs/heads/unrelated)" = "$base_sha" ] \
        || fail "$raced_ref race moved an unrelated head"
done

new_fixture rejected
cat >"$fork/hooks/pre-receive" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$fork/hooks/pre-receive"
expect_bootstrap_failure 'atomic bootstrap push failed' --apply
assert_unmodified_targets

new_fixture extra-carry
git -C "$checkout" branch carry/uninventoried main
expect_bootstrap_failure \
    'bootstrap requires exactly the declared carries' --check

new_fixture missing-carry
git -C "$checkout" branch -D carry/voice-sidecar >/dev/null
expect_bootstrap_failure 'local carry/voice-sidecar is missing' --check

new_fixture bad-ancestry
empty_tree=$(git -C "$checkout" mktree </dev/null)
bad_sha=$(printf 'bad root\n' \
    | git -C "$checkout" "${git_identity[@]}" commit-tree "$empty_tree")
git -C "$checkout" branch --force carry/voice-sidecar "$bad_sha"
git -C "$checkout" branch --force carry/fx-authorization "$bad_sha"
expect_bootstrap_failure 'does not contain upstream/main' --check

new_fixture unbased-authorization
git -C "$checkout" branch --force carry/fx-authorization "$base_sha"
expect_bootstrap_failure 'is not based on' --check

new_fixture missing-local-receipt
rm -f -- "$state/local-builds/$integration_sha.json"
expect_bootstrap_failure 'no private regular local-build receipt' --check

new_fixture production-remote-override
set +e
production_remote_output=$(
    CODPIECE_TESTING=0 \
    CODPIECE_CODEX_CHECKOUT="$checkout" \
    CODPIECE_FORK_URL="$fork" \
    CODPIECE_UPSTREAM_URL="$upstream" \
    CODPIECE_STATE_DIR="$state" \
        "$root/scripts/bootstrap-branches.sh" --check 2>&1
)
production_remote_status=$?
set -e
[ "$production_remote_status" -ne 0 ] \
    || fail "bootstrap accepted a production local-remote override"
printf '%s\n' "$production_remote_output" \
    | grep -F 'fork remote points at' >/dev/null \
    || fail "production remote override refusal was not explained"

new_fixture leaked-test-remote
git -C "$checkout" remote set-url fork https://github.com/possibilities/codex.git
expect_bootstrap_failure 'test mode refuses non-local fork remote' --check

maintain_fixture="$case_root/maintain-skill"
mkdir -p "$maintain_fixture/scripts"
cat >"$maintain_fixture/scripts/reconcile-branches.sh" <<'EOF'
#!/bin/bash
printf 'delegated unexpectedly\n' >&2
exit 1
EOF
chmod 0755 "$maintain_fixture/scripts/reconcile-branches.sh"
set +e
reconcile_remote_output=$(
    CODPIECE_TESTING=1 \
    CODPIECE_CODEX_CHECKOUT="$checkout" \
    MAINTAIN_SKILL_DIR="$maintain_fixture" \
        "$root/scripts/reconcile-branches.sh" --check 2>&1
)
reconcile_remote_status=$?
set -e
[ "$reconcile_remote_status" -ne 0 ] \
    || fail "reconcile accepted a non-local test remote"
printf '%s\n' "$reconcile_remote_output" \
    | grep -F 'test mode refuses non-local fork remote' >/dev/null \
    || fail "reconcile non-local test remote refusal was not explained"

printf 'codpiece bootstrap transaction tests passed.\n'
