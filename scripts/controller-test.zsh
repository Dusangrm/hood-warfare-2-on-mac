#!/bin/zsh
set -eu
source "${0:A:h}/common.zsh"
hood_paths "${0:A:h:h}"
hood_owned
hood_runtime
print -- 'Choose the XInput tab. Move sticks and press buttons to check their readings.'
"$WINE" control joy.cpl >>"$HOOD_LOGS/controller-test.log" 2>&1
