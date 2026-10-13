#!/bin/zsh
set -eu
repo="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/hood-lifecycle.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
checks=0
pass() { (( ++checks )); print -- "ok $checks - $1"; }
fail() { print -u2 -- "not ok - $1"; exit 1; }

# Exercise the real traps through a failing function: plain EXIT is insufficient
# for zsh ERR_EXIT in this situation, and previously left the installer locked.
cat > "$test_root/failing.zsh" <<'ZSH'
set -eu
source "$1/scripts/common.zsh"
hood_paths "$2"
mkdir -p "$HOOD_ROOT"
trap 'hood_exit=$?; hood_cleanup; exit $hood_exit' ZERR
trap hood_cleanup EXIT
hood_lock_acquire
stage="$(mktemp -d "$HOOD_ROOT/.assemble.XXXXXX")"
print data > "$stage/partial"
failing_function() { false; }
failing_function
ZSH
code=0
/bin/zsh "$test_root/failing.zsh" "$repo" "$test_root/failure" || code=$?
[[ "$code" == 1 ]] || fail 'failed function keeps its exit status'
[[ ! -e "$test_root/failure/.install-lock" ]] || fail 'failed function releases its lock'
leftovers=("$test_root/failure"/.assemble.*(N))
(( ${#leftovers} == 0 )) || fail 'failed function removes assembly stage'
pass 'function failure cleans stage and lock and preserves status'

# Transfer lock ownership across exec; no interval permits a second installer.
cat > "$test_root/receiver.zsh" <<'ZSH'
set -eu
source "$1/scripts/common.zsh"
hood_paths "$2"
trap 'hood_exit=$?; hood_cleanup; exit $hood_exit' ZERR
trap hood_cleanup EXIT
hood_lock_acquire
[[ "$(<"$HOOD_ROOT/.install-lock/owner")" == "$$" ]]
print inherited > "$HOOD_ROOT/result"
ZSH
cat > "$test_root/sender.zsh" <<'ZSH'
set -eu
source "$1/scripts/common.zsh"
hood_paths "$2"
mkdir -p "$HOOD_ROOT"
trap 'hood_exit=$?; hood_cleanup; exit $hood_exit' ZERR
trap hood_cleanup EXIT
hood_lock_acquire
exec /bin/zsh "$3" "$1" "$2"
ZSH
/bin/zsh "$test_root/sender.zsh" "$repo" "$test_root/handoff" "$test_root/receiver.zsh"
[[ "$(<"$test_root/handoff/result")" == inherited && ! -e "$test_root/handoff/.install-lock" ]] || fail 'exec handoff'
pass 'exec inherits the same lock and receiver releases it'

source "$repo/scripts/common.zsh"
hood_paths "$test_root/contended"
mkdir -p "$HOOD_ROOT/.install-lock"
print unrelated > "$HOOD_ROOT/.install-lock/owner"
if hood_lock_acquire 2>/dev/null; then fail 'contended lock is refused'; fi
hood_cleanup
[[ "$(<"$HOOD_ROOT/.install-lock/owner")" == unrelated ]] || fail 'unowned lock remains intact'
pass 'a second setup cannot acquire or remove an existing lock'

hood_paths "$test_root/background"
mkdir -p "$HOOD_ROOT"
hood_lock_acquire
( hood_cleanup )
[[ -f "$HOOD_ROOT/.install-lock/owner" ]] || fail 'background cleanup removed parent lock'
hood_cleanup
[[ ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'parent cannot remove own lock'
pass 'background subshell cleanup cannot release the parent lock'

hood_paths "$test_root/shutdown"
mkdir -p "$HOOD_PREFIX" "$HOOD_LOGS"
export WINEPREFIX="$HOOD_PREFIX"
expected_prefix="$HOOD_PREFIX"
WINE=mock_wine
WINESERVER=mock_server
events="$test_root/events"
valid='"tasklist.exe","12","Console","1","1,000 K"'
steam_row='"steam.exe","24","Console","1","2,000 K"'
game_row='"HW2-HoodWarfare2-Win64-Shipping.exe","16","Console","1","1,000 K"'
reset_shutdown() {
  mock_mode="${1:-live}"
  listing_fixture="$valid"
  : > "$events"
  rm -f "$test_root/shutdown-requested" "$test_root/server-stopped" "$test_root/server-stop-attempted"
}
mock_scope() {
  [[ "$WINEPREFIX" == "$expected_prefix" ]] || fail 'shutdown escaped its dedicated prefix'
}
mock_wine() {
  mock_scope
  if [[ "$1" != tasklist ]]; then
    [[ "$1" == 'C:\Program Files (x86)\Steam\Steam.exe' && "${2:-}" == -shutdown ]] || fail 'unexpected Wine operation'
    print shutdown >> "$events"
    [[ "$mock_mode" != shutdown-error ]] || return 7
    touch "$test_root/shutdown-requested"
    return 0
  fi
  print tasklist >> "$events"
  [[ "$mock_mode" != tasklist-error ]] || return 7
  case "$mock_mode" in
    graceful|disappear|shutdown-error|timeout|game-race)
      if [[ "$mock_mode" == timeout || ! -e "$test_root/shutdown-requested" ]]; then
        print -r -- "$valid"$'\n'"$steam_row"
      elif [[ "$mock_mode" == game-race ]]; then
        print -r -- "$valid"$'\n'"$game_row"
      else
        print -r -- "$valid"
      fi
      return 0 ;;
  esac
  print -r -- "$listing_fixture"
}
mock_server() {
  mock_scope
  print -r -- "server $*" >> "$events"
  case "$1" in
    -k0)
      [[ ! -e "$test_root/server-stopped" ]] || return 1
      case "$mock_mode" in
        idle) return 1 ;;
        probe-error) print -u2 -- 'simulated probe failure'; return 1 ;;
        probe-status) return 127 ;;
        disappear) [[ ! -e "$test_root/shutdown-requested" ]] || return 1 ;;
        stop-probe-error)
          if [[ -e "$test_root/server-stop-attempted" ]]; then
            print -u2 -- 'simulated probe failure after stop'; return 1
          fi ;;
      esac
      return 0 ;;
    -k)
      touch "$test_root/server-stop-attempted"
      case "$mock_mode" in
        stop-race) touch "$test_root/server-stopped"; return 1 ;;
        stop-error|stop-probe-error) return 1 ;;
      esac
      touch "$test_root/server-stopped"; return 0 ;;
    -w) return 0 ;;
    *) fail 'unexpected wineserver operation' ;;
  esac
}
sleep() { print sleep >> "$events"; }
no_stop_actions() {
  ! /usr/bin/grep -Eq '^(shutdown|server -k|server -w)$' "$events"
}

reset_shutdown idle
hood_stop_steam quit >/dev/null
[[ "$(<"$events")" == 'server -k0' ]] || fail 'idle Quit started Wine or sent a stop command'
pass 'already-stopped Quit uses only a no-start server probe'

for mode in probe-error probe-status; do
  reset_shutdown "$mode"
  if hood_stop_steam quit >/dev/null 2>&1; then fail 'probe failure was mistaken for absence'; fi
  [[ "$(<"$events")" == 'server -k0' ]] || fail 'failed probe performed other actions'
done
pass 'probe diagnostics and unexpected status fail without starting Wine'

reset_shutdown
for listing_fixture in '' 'Some error' '"tasklist.exe","12","Console","1","1,000 K"'$'\n''broken' '"steam.exe","32","Console","1","2,000 K"'; do
  if hood_stop_steam >/dev/null 2>&1; then fail 'invalid tasklist was accepted'; fi
  no_stop_actions || fail 'invalid tasklist stopped a process'
done
pass 'empty, malformed and incomplete tasklists fail closed'

for game in "$game_row" '"HW2.exe","16","Console","1","1,000 K"'; do
  reset_shutdown
  listing_fixture="$valid"$'\n'"$steam_row"$'\n'"$game"
  if hood_stop_steam quit >/dev/null 2>&1; then fail 'running game was accepted'; fi
  no_stop_actions || fail 'running game was stopped'
done
pass 'both game executable names prevent all shutdown actions'

reset_shutdown
hood_stop_steam >/dev/null
[[ "$(<"$events")" == $'server -k0\ntasklist\nserver -k0\ntasklist\nserver -k\nserver -w' ]] || fail 'stopped Steam should only stop its existing server'
pass 'a live runtime without Steam closes only its dedicated server'

reset_shutdown graceful
hood_stop_steam quit >/dev/null
[[ "$(<"$events")" == $'server -k0\ntasklist\nshutdown\nserver -k0\ntasklist\nserver -k\nserver -w' ]] || fail 'shutdown did not wait for Steam before closing its server'
pass 'graceful shutdown precedes server shutdown, all calls scoped to the prefix'

reset_shutdown disappear
hood_stop_steam quit >/dev/null
[[ "$(<"$events")" == $'server -k0\ntasklist\nshutdown\nserver -k0' ]] || fail 'polling restarted Wine after its server exited'
pass 'server exit during shutdown prevents every later Wine invocation'

reset_shutdown stop-race
hood_stop_steam quit >/dev/null
[[ "$(<"$events")" == $'server -k0\ntasklist\nserver -k0\ntasklist\nserver -k\nserver -k0' ]] || fail 'natural exit after listing was not handled with one no-start recheck'
pass 'natural server exit before the stop request counts as successful shutdown'

reset_shutdown stop-error
if hood_stop_steam quit >/dev/null 2>&1; then fail 'failed stop of a live server returned success'; fi
[[ "$(<"$events")" == $'server -k0\ntasklist\nserver -k0\ntasklist\nserver -k\nserver -k0' ]] || fail 'failed server stop retried or waited unsafely'
pass 'a failed stop with a still-live server fails without retrying or waiting'

reset_shutdown stop-probe-error
if hood_stop_steam quit >/dev/null 2>&1; then fail 'failed post-stop probe was mistaken for success'; fi
[[ "$(<"$events")" == $'server -k0\ntasklist\nserver -k0\ntasklist\nserver -k\nserver -k0' ]] || fail 'failed post-stop probe performed extra actions'
pass 'an error rechecking a failed server stop fails closed'

reset_shutdown timeout
if hood_stop_steam quit >/dev/null 2>&1; then fail 'hung Steam returned success'; fi
[[ "$(/usr/bin/grep -c '^shutdown$' "$events")" == 1 ]] || fail 'hung Steam was repeatedly restarted'
! /usr/bin/grep -Eq '^server -(k|w)$' "$events" || fail 'timeout forced a server shutdown'
[[ "$(/usr/bin/grep -c '^sleep$' "$events")" == 45 ]] || fail 'shutdown wait was not bounded'
pass 'hung Steam times out without repeated shutdown launches or a forced stop'

reset_shutdown tasklist-error
if hood_stop_steam quit >/dev/null 2>&1; then fail 'failed tasklist returned success'; fi
no_stop_actions || fail 'failed tasklist stopped a process'
pass 'tasklist execution failure leaves the runtime untouched'

reset_shutdown game-race
if hood_stop_steam quit >/dev/null 2>&1; then fail 'newly started game was ignored'; fi
! /usr/bin/grep -Eq '^server -(k|w)$' "$events" || fail 'game starting during shutdown was killed'
pass 'a game starting during Steam shutdown prevents server termination'

unfunction sleep

# Run the real Finish Setup script against a sanitized installation with mocked
# executables. This proves a completed setup repairs reset launch options.
hood_paths "$test_root/resume"
mkdir -p "$HOOD_TOOLS" "$HOOD_LOGS" "$HOOD_APP/Contents/MacOS" "$HOOD_APP/Contents/SharedSupport/wine/bin" "$HOOD_GAME/HW2/Binaries/Win64" "$HOOD_STEAM/userdata/123/config"
touch "$HOOD_ROOT/.hood-on-mac" "$HOOD_ROOT/.components-ready" "$HOOD_ROOT/.setup-complete"
touch "$HOOD_GAME/HW2/Binaries/Win64/HW2-HoodWarfare2-Win64-Shipping.exe"
print -r -- '"AppState" { "StateFlags" "4" }' > "$HOOD_STEAM/steamapps/appmanifest_5155360.acf"
print -r -- '"UserLocalConfigStore" {}' > "$HOOD_STEAM/userdata/123/config/localconfig.vdf"
print -r -- '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$HOOD_PLIST"
cp "$repo/scripts/"{common.zsh,finish.zsh,steam-options.pl} "$HOOD_TOOLS/"
cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wine" <<'SH'
#!/bin/zsh
[[ "$1" == tasklist ]] || exit 7
print -r -- '"tasklist.exe","12","Console","1","1,000 K"'
SH
cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wineserver" <<'SH'
#!/bin/zsh
exit 0
SH
cat > "$HOOD_APP/Contents/MacOS/launcher" <<'SH'
#!/bin/zsh
[[ ! -e "${0:A:h:h:h:h}/.install-lock" ]] || exit 9
SH
chmod +x "$HOOD_APP/Contents/SharedSupport/wine/bin/"{wine,wineserver} "$HOOD_APP/Contents/MacOS/launcher"
/bin/zsh "$HOOD_TOOLS/finish.zsh" >/dev/null
/usr/bin/perl "$HOOD_TOOLS/steam-options.pl" --file "$HOOD_STEAM/userdata/123/config/localconfig.vdf" --check >/dev/null
[[ ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'Finish leaves a lock'
[[ "$(/usr/libexec/PlistBuddy -c "Print ':Program Flags'" "$HOOD_PLIST")" == '-applaunch 5155360 -windowed -ResX=1280 -ResY=720' ]] || fail 'Finish did not restore game flags'
pass 'Finish repairs a completed setup and releases its lock before launch'

print -r -- '"UserLocalConfigStore" {' > "$HOOD_STEAM/userdata/123/config/localconfig.vdf"
code=0
/bin/zsh "$HOOD_TOOLS/finish.zsh" >/dev/null 2>&1 || code=$?
[[ "$code" != 0 && ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'failed repair does not release its lock'
[[ "$(<"$HOOD_STEAM/userdata/123/config/localconfig.vdf")" == '"UserLocalConfigStore" {' ]] || fail 'failed repair modified malformed config'
pass 'failed Finish repair preserves data and releases its lock for retry'

cp "$repo/scripts/quit.zsh" "$HOOD_TOOLS/"
cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wine" <<'SH'
#!/bin/zsh
touch "$WINEPREFIX/unexpected-wine-invocation"
exit 99
SH
cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wineserver" <<'SH'
#!/bin/zsh
[[ "$1" == -k0 ]] || exit 99
exit 1
SH
/bin/zsh "$HOOD_TOOLS/quit.zsh" >/dev/null
[[ ! -e "$HOOD_PREFIX/unexpected-wine-invocation" && ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'idle Quit shortcut booted Wine or left a lock'
pass 'the actual Quit script is idempotent when its runtime is stopped'

mkdir "$HOOD_ROOT/.install-lock"
print unrelated > "$HOOD_ROOT/.install-lock/owner"
code=0
/bin/zsh "$HOOD_TOOLS/quit.zsh" >/dev/null 2>&1 || code=$?
[[ "$code" != 0 && "$(<"$HOOD_ROOT/.install-lock/owner")" == unrelated ]] || fail 'Quit interfered with another setup lock'
[[ ! -e "$HOOD_PREFIX/unexpected-wine-invocation" ]] || fail 'contended Quit called Wine'
rm "$HOOD_ROOT/.install-lock/owner"
rmdir "$HOOD_ROOT/.install-lock"
pass 'the actual Quit script refuses an active setup without touching its lock'

cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wine" <<'SH'
#!/bin/zsh
if [[ "$1" == tasklist ]]; then
  print -r -- '"tasklist.exe","12","Console","1","1,000 K"'
  print -r -- '"steam.exe","24","Console","1","2,000 K"'
  exit 0
fi
exit 7
SH
cat > "$HOOD_APP/Contents/SharedSupport/wine/bin/wineserver" <<'SH'
#!/bin/zsh
[[ "$1" == -k0 ]] || touch "$WINEPREFIX/unexpected-server-stop"
exit 0
SH
code=0
/bin/zsh "$HOOD_TOOLS/quit.zsh" >/dev/null 2>&1 || code=$?
[[ "$code" != 0 && ! -e "$HOOD_PREFIX/unexpected-server-stop" && ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'failed Steam shutdown killed its server or retained a lock'
pass 'a failed Steam shutdown stops Quit safely and releases the lock'

print -- "1..$checks"
