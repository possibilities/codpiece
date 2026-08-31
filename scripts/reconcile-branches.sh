#!/bin/bash

set -euo pipefail

# Codpiece's thin adapter to the maintain skill's shared namespace policy.
# This file declares the branch model and contains no reconciliation mechanics.

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$root/scripts/gate-contract.sh"

die() {
    printf 'codpiece branches: %s\n' "$*" >&2
    exit 1
}

skill_dir="${MAINTAIN_SKILL_DIR:-$HOME/.local/share/agentstart/resources/skills/maintain}"
script="$skill_dir/scripts/reconcile-branches.sh"
if [ ! -f "$script" ]; then
    die "the maintain skill is not installed at $skill_dir (run ~/code/agentstart/scripts/install.sh --install, or set MAINTAIN_SKILL_DIR)"
fi

checkout="${CODPIECE_CODEX_CHECKOUT:-$HOME/src/codex}"
test_mode="${CODPIECE_TESTING:-0}"
case "$test_mode" in 0|1) ;; *) die "CODPIECE_TESTING must be 0 or 1" ;; esac
if [ "$test_mode" -eq 1 ]; then
    actual_fork=$(git -C "$checkout" remote get-url fork 2>/dev/null) \
        || die "$checkout has no fork remote"
    actual_origin=$(git -C "$checkout" remote get-url origin 2>/dev/null) \
        || die "$checkout has no origin remote"
    codpiece_require_local_test_remote fork "$actual_fork" \
        || die "test mode remote safety check failed"
    codpiece_require_local_test_remote origin "$actual_origin" \
        || die "test mode remote safety check failed"
fi
expected_carry=carry/voice-sidecar
actual_carries=$(git -C "$checkout" for-each-ref \
    --format='%(refname:short)' refs/heads/carry/ | LC_ALL=C sort)
if [ "$actual_carries" != "$expected_carry" ]; then
    printf 'codpiece branches: active voice-only phase requires exactly local %s\n' \
        "$expected_carry" >&2
    exit 1
fi
if git -C "$checkout" show-ref --verify --quiet refs/heads/integration; then
    integration_sha=$(git -C "$checkout" rev-parse refs/heads/integration)
    carry_sha=$(git -C "$checkout" rev-parse "refs/heads/$expected_carry")
    if [ "$integration_sha" != "$carry_sha" ]; then
        printf 'codpiece branches: voice-only Integration must exactly equal %s\n' \
            "$expected_carry" >&2
        exit 1
    fi
fi

export MAINTAIN_CHECKOUT="$checkout"
export MAINTAIN_FORK_REPO=possibilities/codex
export MAINTAIN_UPSTREAM_REPO=openai/codex
export MAINTAIN_FORK_REMOTE=fork
export MAINTAIN_UPSTREAM_REMOTE=origin
export MAINTAIN_MAIN_BRANCH=main
export MAINTAIN_INTEGRATION_BRANCH=integration
export MAINTAIN_CARRY_PREFIX=carry/
export MAINTAIN_QUARANTINE_PREFIX=DELETEME/
export MAINTAIN_PRESERVE_OPEN_PRS=0
if [ "$test_mode" -eq 1 ]; then
    export MAINTAIN_ALLOW_LOCAL_REMOTES=1
fi

exec bash "$script" "$@"
