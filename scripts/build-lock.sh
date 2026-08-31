#!/bin/bash

# Shared machine-local mutex for every Codpiece release build or installation.
# The caller owns EXIT trapping and must invoke codpiece_release_lock_release.

codpiece_release_lock_acquire() {
    local state_root=$1
    CODPIECE_RELEASE_LOCK="$state_root/release.lock"
    mkdir -p "$state_root"
    chmod 0700 "$state_root"
    if ! mkdir -m 0700 "$CODPIECE_RELEASE_LOCK" 2>/dev/null; then
        printf 'codpiece: another release build or installation owns %s\n' \
            "$CODPIECE_RELEASE_LOCK" >&2
        return 1
    fi
    printf '%s\n' "$$" >"$CODPIECE_RELEASE_LOCK/pid"
}

codpiece_release_lock_release() {
    if [ -n "${CODPIECE_RELEASE_LOCK:-}" ] \
        && [ -d "$CODPIECE_RELEASE_LOCK" ]; then
        rm -f -- "$CODPIECE_RELEASE_LOCK/pid" || return 1
        rmdir "$CODPIECE_RELEASE_LOCK" || return 1
    fi
    CODPIECE_RELEASE_LOCK=
}
