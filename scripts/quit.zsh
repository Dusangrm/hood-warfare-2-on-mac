#!/bin/zsh
set -eu
source "${0:A:h}/common.zsh"
hood_paths "${0:A:h:h}"
hood_owned
trap 'hood_exit=$?; hood_cleanup; exit $hood_exit' ZERR
trap hood_cleanup EXIT
trap 'exit 130' INT TERM
hood_lock_acquire
hood_runtime
hood_stop_steam quit
print -- 'This installation of Windows Steam is closed.'
