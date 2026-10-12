#!/bin/zsh
set -eu
source "${0:A:h}/common.zsh"
hood_paths "${0:A:h:h}"
hood_owned
if [[ ! -f "$HOOD_ROOT/.setup-complete" ]]; then
  exec /bin/zsh "$HOOD_TOOLS/finish.zsh"
fi
hood_native >>"$HOOD_LOGS/launcher.log" 2>&1
