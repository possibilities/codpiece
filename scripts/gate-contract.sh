#!/bin/bash

# Shared by every producer and consumer of Codpiece's exact-SHA receipts.

# shellcheck disable=SC2034 # Sourced constants used by gate/install scripts.
CODPIECE_CANONICAL_FORK_URL=https://github.com/possibilities/codex.git
# shellcheck disable=SC2034 # Sourced constants used by gate/install scripts.
CODPIECE_CANONICAL_UPSTREAM_URL=https://github.com/openai/codex.git

codpiece_gate_contract_digest() {
    local root=$1 file
    for file in \
        "$root/MAINTAIN.md" \
        "$root/gate/budgets.json" \
        "$root/gate/first-party-allowlist.txt" \
        "$root/scripts/build-lock.sh" \
        "$root/scripts/gate-contract.sh" \
        "$root/scripts/gate.sh" \
        "$root/scripts/bootstrap-branches.sh" \
        "$root/scripts/reconcile-branches.sh" \
        "$root/scripts/install.sh"; do
        [ -f "$file" ] || return 1
        shasum -a 256 "$file" | awk '{print $1}'
    done | shasum -a 256 | awk '{print $1}'
}

codpiece_full_sha() {
    [ "${#1}" -eq 40 ] || return 1
    case "$1" in
        *[!0-9a-f]*) return 1 ;;
        *) return 0 ;;
    esac
}

codpiece_regular_private_receipt() {
    local receipt=$1
    [ -f "$receipt" ] && [ ! -L "$receipt" ] || return 1
    [ "$(stat -f '%u' "$receipt")" = "$(id -u)" ] || return 1
    [ "$(stat -f '%Lp' "$receipt")" = 600 ] || return 1
}

codpiece_test_remote_is_local() {
    local remote=$1
    case "$remote" in
        /* | ./* | ../* | file:///*) return 0 ;;
        *) return 1 ;;
    esac
}

codpiece_require_local_test_remote() {
    local label=$1 remote=$2
    if ! codpiece_test_remote_is_local "$remote"; then
        printf 'codpiece: test mode refuses non-local %s remote: %s\n' \
            "$label" "$remote" >&2
        return 1
    fi
}

codpiece_remote_matches() {
    local actual=$1 expected=$2 ssh
    ssh="git@github.com:${expected#https://github.com/}"
    case "$actual" in
        "$expected" | "${expected%.git}" | "$ssh" | "${ssh%.git}") return 0 ;;
        *) return 1 ;;
    esac
}

codpiece_remote_head() {
    local checkout=$1 remote=$2 ref=$3 label=$4 listing sha
    listing=$(git -C "$checkout" ls-remote --heads "$remote" "$ref") || return 1
    sha=$(printf '%s\n' "$listing" | awk 'NR == 1 { print $1 }')
    [ -n "$sha" ] || {
        printf 'codpiece: remote %s is missing\n' "$label" >&2
        return 1
    }
    codpiece_full_sha "$sha" || {
        printf 'codpiece: remote %s did not resolve to a full SHA\n' "$label" >&2
        return 1
    }
    printf '%s\n' "$sha"
}

