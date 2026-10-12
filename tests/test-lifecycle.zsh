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

HOOD_LOGS="$test_root"
WINE=mock_wine
WINESERVER=mock_server
mock_wine() {
  [[ "$1" == tasklist ]] || { print shutdown >> "$test_root/actions"; return 0; }
  print -r -- "$listing_fixture"
}
mock_server() { print -r -- "server $*" >> "$test_root/actions"; }
valid='"tasklist.exe","12","Console","1","1,000 K"'
for listing_fixture in '' 'Some error' '"tasklist.exe","12","Console","1","1,000 K"'$'\n''broken' '"steam.exe","32","Console","1","2,000 K"'; do
  if hood_stop_steam >/dev/null 2>&1; then fail 'invalid tasklist was accepted'; fi
  [[ ! -e "$test_root/actions" ]] || fail 'invalid tasklist stopped a process'
done
pass 'empty, malformed and incomplete tasklists fail closed'
listing_fixture="$valid"$'\n''"HW2-HoodWarfare2-Win64-Shipping.exe","16","Console","1","1,000 K"'
if hood_stop_steam >/dev/null 2>&1; then fail 'running game was accepted'; fi
[[ ! -e "$test_root/actions" ]] || fail 'running game was stopped'
pass 'an active game prevents all shutdown actions'
listing_fixture="$valid"
hood_stop_steam >/dev/null
[[ "$(<"$test_root/actions")" == $'server -k\nserver -w' ]] || fail 'stopped Steam should only stop its own server'
pass 'valid tasklist permits dedicated-prefix server shutdown'

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
exit 0
SH
chmod +x "$HOOD_APP/Contents/SharedSupport/wine/bin/"{wine,wineserver} "$HOOD_APP/Contents/MacOS/launcher"
/bin/zsh "$HOOD_TOOLS/finish.zsh" >/dev/null
/usr/bin/perl "$HOOD_TOOLS/steam-options.pl" --file "$HOOD_STEAM/userdata/123/config/localconfig.vdf" --check >/dev/null
[[ ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'Finish leaves a lock'
[[ "$(/usr/libexec/PlistBuddy -c "Print ':Program Flags'" "$HOOD_PLIST")" == '-applaunch 5155360 -windowed -ResX=1280 -ResY=720' ]] || fail 'Finish did not restore game flags'
pass 'Finish repairs a completed setup and releases the operation lock'

print -r -- '"UserLocalConfigStore" {' > "$HOOD_STEAM/userdata/123/config/localconfig.vdf"
code=0
/bin/zsh "$HOOD_TOOLS/finish.zsh" >/dev/null 2>&1 || code=$?
[[ "$code" != 0 && ! -e "$HOOD_ROOT/.install-lock" ]] || fail 'failed repair does not release its lock'
[[ "$(<"$HOOD_STEAM/userdata/123/config/localconfig.vdf")" == '"UserLocalConfigStore" {' ]] || fail 'failed repair modified malformed config'
pass 'failed Finish repair preserves data and releases its lock for retry'

print -- "1..$checks"
