#!/bin/zsh
set -eu
exec /bin/zsh "${0:A:h}/scripts/install.zsh" "$@"
