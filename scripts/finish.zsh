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
[[ -f "$HOOD_ROOT/.components-ready" ]] || { hood_fail 'Run Install.command again to finish installing the prerequisites.'; exit 1; }
if ! hood_game_ready; then
  print -- 'Sign into Windows Steam with the account that owns Hood Warfare 2.'
  print -- 'Install it in the default library. This window waits for the download.'
  print -- 'You can cancel with Control-C and resume with Finish Setup.command.'
  # Initial Program Flags contain Steam's install URI. Use the configured
  # default, because this template's legacy alternate-exe mode ignores flags.
  hood_native >>"$HOOD_LOGS/launcher.log" 2>&1 &
  while ! hood_game_ready; do sleep 4; done
fi
print -- 'Download complete. Applying the game launch fix…'
hood_stop_steam
configs=("$HOOD_STEAM"/userdata/<->/config/localconfig.vdf(N))
(( ${#configs} > 0 )) || { hood_fail 'Steam has not saved a signed-in account yet. Sign in, exit Steam, then run Finish Setup.'; exit 1; }
for config in "${configs[@]}"; do
  /usr/bin/perl "$HOOD_TOOLS/steam-options.pl" --file "$config"
done
hood_plist 'Program Flags' string '-applaunch 5155360 -windowed -ResX=1280 -ResY=720'
print -- '1' > "$HOOD_ROOT/.setup-complete"
print -- 'Ready. Next time, open Hood Warfare 2.app or Play Hood Warfare 2.command.'
hood_native >>"$HOOD_LOGS/launcher.log" 2>&1
