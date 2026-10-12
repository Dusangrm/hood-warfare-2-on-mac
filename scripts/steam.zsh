#!/bin/zsh
set -eu
source "${0:A:h}/common.zsh"
hood_paths "${0:A:h:h}"
hood_owned
# The template's wineskinlauncher alias selects legacy syntax: the first arg is
# the executable, with empty flags. Modern "run" syntax does not apply here.
hood_native 'C:\Program Files (x86)\Steam\Steam.exe' >>"$HOOD_LOGS/launcher.log" 2>&1
