# Shared by the installed tools. Requires zsh; paths never depend on the user name.
hood_fail() { print -u2 -- "Error: $*"; return 1; }
hood_paths() {
  HOOD_ROOT="${1:A}"
  HOOD_APP="$HOOD_ROOT/Hood Warfare 2.app"
  HOOD_PLIST="$HOOD_APP/Contents/Info.plist"
  HOOD_TOOLS="$HOOD_ROOT/Tools"
  HOOD_LOGS="$HOOD_ROOT/Logs"
  HOOD_PREFIX="$HOOD_APP/Contents/SharedSupport/prefix"
  HOOD_STEAM="$HOOD_PREFIX/drive_c/Program Files (x86)/Steam"
  HOOD_GAME="$HOOD_STEAM/steamapps/common/Hood Warfare 2"
}
hood_lock_acquire() {
  local lock="$HOOD_ROOT/.install-lock"
  # exec preserves the installer's PID, so Finish Setup can inherit its lock.
  if [[ "${HOOD_SETUP_LOCK_PID:-}" == "$$" && -d "$lock" && ! -L "$lock" && -f "$lock/owner" && ! -L "$lock/owner" && "$(<"$lock/owner")" == "$$" ]]; then
    HOOD_LOCK_HELD=1
    return 0
  fi
  mkdir "$lock" 2>/dev/null || { hood_fail 'Setup is already running. If a previous run crashed, remove .install-lock in the installation folder and retry.'; return 1; }
  HOOD_LOCK_HELD=1
  export HOOD_SETUP_LOCK_PID=$$
  print -r -- "$$" > "$lock/owner"
}
hood_cleanup_stage() {
  if [[ -n "${stage:-}" && "$stage" == "$HOOD_ROOT"/.assemble.* && -d "$stage" && ! -L "$stage" ]]; then
    rm -rf -- "$stage" || true
  fi
  stage=''
  return 0
}
hood_cleanup() {
  # Background Wine launchers inherit traps, but never own the parent's lock.
  (( ZSH_SUBSHELL == 0 )) || return 0
  hood_cleanup_stage
  if [[ -n "${download_part:-}" && -n "${cache:-}" && "$download_part" == "$cache"/* && -f "$download_part" && ! -L "$download_part" ]]; then
    rm -f -- "$download_part" || true
  fi
  if [[ "${HOOD_LOCK_HELD:-0}" == 1 ]]; then
    HOOD_LOCK_HELD=0
    rm -f -- "$HOOD_ROOT/.install-lock/owner" 2>/dev/null || true
    rmdir "$HOOD_ROOT/.install-lock" 2>/dev/null || true
  fi
  return 0
}
hood_owned() {
  [[ -f "$HOOD_ROOT/.hood-on-mac" && ! -L "$HOOD_ROOT/.hood-on-mac" ]] || hood_fail 'This is not an installation created by this installer.'
  [[ -d "$HOOD_APP/Contents/SharedSupport/wine" && ! -L "$HOOD_APP" ]] || hood_fail 'The installed compatibility engine is missing.'
}
hood_plist() {
  local key="$1" type="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Set ':$key' '$value'" "$HOOD_PLIST" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add ':$key' $type '$value'" "$HOOD_PLIST"
}
hood_layout_env() {
  local layout=positions
  [[ ! -f "$HOOD_ROOT/controller-layout" ]] || layout="$(<"$HOOD_ROOT/controller-layout")"
  case "$layout" in
    positions|keyboard) export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0 ;;
    labels) export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1 ;;
    *) hood_fail 'Invalid controller preference. Run Controller Layout.command.'; return 1 ;;
  esac
}
hood_runtime() {
  local engine="$HOOD_APP/Contents/SharedSupport/wine"
  local frameworks="$HOOD_APP/Contents/Frameworks"
  local metal="$frameworks/renderer/d3dmetal"
  export WINEPREFIX="$HOOD_PREFIX" WINE="$engine/bin/wine" WINESERVER="$engine/bin/wineserver"
  export WINELOADER="$WINE" WINEDLLPATH="$engine/lib/wine"
  export DYLD_FALLBACK_LIBRARY_PATH="$frameworks:$frameworks/GStreamer.framework/Libraries:$metal/external:$engine/lib:/usr/lib"
  export GST_PLUGIN_PATH="$frameworks/GStreamer.framework/Libraries/gstreamer-1.0"
  export SikarugirAppWine11=1 WINEESYNC=1 WINEMSYNC=1 WINEDEBUG=-all ROSETTA_ADVERTISE_AVX=1
  export WINEDLLPATH_DXMT="$frameworks/renderer/dxmt/wine"
  export WINEDLLPATH_D3DMETAL="$metal/wine" CX_D3DMETALPATH="$metal"
  export CX_APPLEGPT_LIBD3DSHARED_PATH="$metal/external/libd3dshared.dylib"
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="$CX_APPLEGPT_LIBD3DSHARED_PATH"
  hood_layout_env
}
hood_native() {
  hood_layout_env
  "$HOOD_APP/Contents/MacOS/launcher" "$@"
}
hood_process_listing() {
  # tasklist is restricted to this Wine prefix. Never inspect or stop macOS Steam.
  local listing
  listing="$("$WINE" tasklist /FO CSV /NH 2>/dev/null)" || { hood_fail 'Cannot read the Windows process list.'; return 2; }
  # An empty/error/localized table must never be interpreted as Steam exiting.
  print -r -- "$listing" | /usr/bin/perl -ne '
    s/\r?\n\z//; next if /^\s*$/;
    exit 1 unless /^"(?:[^"]|"")+","[0-9]+","(?:[^"]|"")*","[0-9]+","(?:[^"]|"")*"$/;
    $self = 1 if /^"tasklist[.]exe",/i;
    END { exit 1 unless $self; }
  ' || { hood_fail 'Unrecognized Windows process list; setup will not stop any processes or edit Steam.'; return 2; }
  print -r -- "$listing"
}
hood_steam_running() {
  local listing
  listing="$(hood_process_listing)" || return 2
  print -r -- "$listing" | /usr/bin/grep -qi '^"steam[.]exe",'
}
hood_stop_steam() {
  print -- 'Restarting this installation of Windows Steam to save the launch fix…'
  local i listing
  listing="$(hood_process_listing)" || return 1
  if print -r -- "$listing" | /usr/bin/grep -qiE '^"HW2(-HoodWarfare2|[.]exe")'; then
    hood_fail 'Close Hood Warfare 2, then run Finish Setup again.'; return 1
  fi
  if print -r -- "$listing" | /usr/bin/grep -qi '^"steam[.]exe",'; then
    "$WINE" 'C:\Program Files (x86)\Steam\Steam.exe' -shutdown >>"$HOOD_LOGS/setup.log" 2>&1
  fi
  for i in {1..45}; do
    listing="$(hood_process_listing)" || return 1
    if ! print -r -- "$listing" | /usr/bin/grep -qi '^"steam[.]exe",'; then
      if print -r -- "$listing" | /usr/bin/grep -qiE '^"HW2(-HoodWarfare2|[.]exe")'; then
        hood_fail 'Close Hood Warfare 2, then run Finish Setup again.'; return 1
      fi
      # Only this dedicated prefix, after Steam and the game have exited.
      "$WINESERVER" -k
      "$WINESERVER" -w
      return 0
    fi
    sleep 2
  done
  hood_fail 'Steam is still running. Exit this Windows Steam client, then run Finish Setup again.'
}
hood_game_ready() {
  local manifest="$HOOD_STEAM/steamapps/appmanifest_5155360.acf"
  [[ -f "$HOOD_GAME/HW2/Binaries/Win64/HW2-HoodWarfare2-Win64-Shipping.exe" && -f "$manifest" ]] || return 1
  /usr/bin/grep -Eq '"StateFlags"[[:space:]]+"4"' "$manifest"
}
