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
        "$root/scripts/artifact-gate.sh" \
        "$root/scripts/bootstrap-branches.sh" \
        "$root/scripts/reconcile-branches.sh" \
        "$root/scripts/ship-gate.sh" \
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

codpiece_agentvoice_provenance() {
    local agentvoice_root=$1 validator=$2
    local real_root top real_top validator_dir validator_abs validator_rel
    local commit_sha tree_sha validator_sha dependency_files
    local dependency_file dependency_sha

    git -C "$agentvoice_root" rev-parse --is-inside-work-tree \
        >/dev/null 2>&1 || return 1
    real_root=$(cd "$agentvoice_root" && pwd -P) || return 1
    top=$(git -C "$real_root" rev-parse --show-toplevel) || return 1
    real_top=$(cd "$top" && pwd -P) || return 1
    [ "$real_top" = "$real_root" ] || return 1
    [ -z "$(git -C "$real_root" status --porcelain)" ] || return 1

    [ -f "$validator" ] && [ ! -L "$validator" ] || return 1
    validator_dir=$(cd "$(dirname "$validator")" && pwd -P) || return 1
    validator_abs="$validator_dir/$(basename "$validator")"
    case "$validator_abs" in
        "$real_root"/*) ;;
        *) return 1 ;;
    esac
    validator_rel=${validator_abs#"$real_root"/}
    [ "$validator_rel" = src/codpiece-artifact-validator-cli.ts ] || return 1
    git -C "$real_root" ls-files --error-unmatch -- "$validator_rel" \
        >/dev/null 2>&1 || return 1

    commit_sha=$(git -C "$real_root" rev-parse HEAD) || return 1
    tree_sha=$(git -C "$real_root" rev-parse 'HEAD^{tree}') || return 1
    codpiece_full_sha "$commit_sha" || return 1
    codpiece_full_sha "$tree_sha" || return 1
    validator_sha=$(shasum -a 256 "$validator_abs" | awk '{print $1}') \
        || return 1

    dependency_files=$(
        for dependency_file in package.json bun.lock bun.lockb tsconfig.json; do
            if git -C "$real_root" ls-files --error-unmatch -- "$dependency_file" \
                >/dev/null 2>&1; then
                [ -f "$real_root/$dependency_file" ] \
                    && [ ! -L "$real_root/$dependency_file" ] || exit 1
                dependency_sha=$(shasum -a 256 "$real_root/$dependency_file" \
                    | awk '{print $1}') || exit 1
                jq -n \
                    --arg repositoryPath "$dependency_file" \
                    --arg sha256 "$dependency_sha" \
                    '{repositoryPath:$repositoryPath,sha256:$sha256}' \
                    || exit 1
            fi
        done | jq -s .
    ) || return 1
    printf '%s\n' "$dependency_files" | jq -e '
        any(.[]; .repositoryPath == "package.json") and
        (any(.[]; .repositoryPath == "bun.lock") or
         any(.[]; .repositoryPath == "bun.lockb"))
    ' >/dev/null || return 1

    jq -n \
        --arg root "$real_root" \
        --arg commitSha "$commit_sha" \
        --arg treeSha "$tree_sha" \
        --arg validatorPath "$validator_abs" \
        --arg validatorRepositoryPath "$validator_rel" \
        --arg validatorSha "$validator_sha" \
        --argjson dependencyFiles "$dependency_files" \
        '{schemaVersion:1,repository:"agentvoice",root:$root,
          commitSha:$commitSha,treeSha:$treeSha,
          validator:{path:$validatorPath,
            repositoryPath:$validatorRepositoryPath,sha256:$validatorSha},
          dependencyFiles:$dependencyFiles}'
}
