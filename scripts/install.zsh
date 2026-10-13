#!/bin/zsh
set -eu
setopt PIPE_FAIL
script_dir="${0:A:h}"
source "$script_dir/common.zsh"
source "$script_dir/assets.zsh"
destination="$HOME/Applications/Hood Warfare 2 on Mac"
cache="$HOME/Library/Caches/hood-warfare-2-on-mac"
layout=''
no_open=0
prepare_only=0
while (( $# )); do
  case "$1" in
    --destination|--cache|--layout)
      (( $# >= 2 )) || { hood_fail "Missing value for $1"; exit 1; }
      case "$1" in --destination) destination="$2" ;; --cache) cache="$2" ;; --layout) layout="$2" ;; esac
      shift 2 ;;
    --no-open) no_open=1; shift ;;
    --prepare-only) prepare_only=1; no_open=1; shift ;;
    --help)
      print -- 'Install.command [--destination PATH] [--cache PATH] [--layout positions|labels|keyboard] [--no-open] [--prepare-only]'
      print -- '--no-open installs prerequisites without opening Steam; --prepare-only only assembles the app.'
      exit 0 ;;
    *) hood_fail "Unknown option: $1"; exit 1 ;;
  esac
done
case "$layout" in ''|positions|labels|keyboard) ;; *) hood_fail 'Invalid controller layout.'; exit 1 ;; esac
[[ "$(uname -s)" == Darwin ]] || { hood_fail 'This installer requires macOS.'; exit 1; }
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] || { hood_fail 'This setup requires an Apple Silicon Mac (M1 or newer).'; exit 1; }
os_version="$(/usr/bin/sw_vers -productVersion)"
(( ${os_version%%.*} >= 15 )) || { hood_fail 'macOS 15 or newer is required by the graphics layer.'; exit 1; }
(( EUID != 0 )) || { hood_fail 'Run this as your normal user, without sudo.'; exit 1; }
hood_paths "$destination"
[[ "$HOOD_ROOT" != / && "$HOOD_ROOT" != "$HOME" && ! -L "$HOOD_ROOT" ]] || { hood_fail 'Choose a dedicated installation folder.'; exit 1; }
if [[ -d "$HOOD_ROOT" && ! -f "$HOOD_ROOT/.hood-on-mac" ]]; then
  existing=("$HOOD_ROOT"/*(DN))
  (( ${#existing} == 0 )) || { hood_fail 'Destination is not empty. Choose a new folder; existing installations will not be overwritten.'; exit 1; }
fi
mkdir -p "$HOOD_ROOT" "$cache"
available_kb="$(df -Pk "$HOOD_ROOT" | /usr/bin/awk 'NR==2 {print $4}')"
(( available_kb >= 25 * 1024 * 1024 )) || { hood_fail 'At least 25 GB of free space is required for setup and the game.'; exit 1; }
stage=''
download_part=''
# zsh can skip EXIT on ERR_EXIT inside a function; ZERR handles that path.
trap 'hood_exit=$?; hood_cleanup; exit $hood_exit' ZERR
trap hood_cleanup EXIT
trap 'exit 130' INT TERM
hood_lock_acquire
print -- '1' > "$HOOD_ROOT/.hood-on-mac"
mkdir -p "$HOOD_LOGS" "$HOOD_TOOLS"
print -- 'Hood Warfare 2 on Mac — preparing your private installation.'

if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  /usr/bin/osascript <<'APPLESCRIPT'
display dialog "Apple's Rosetta 2 is needed to run Windows Steam. Continue to install it under Apple's Rosetta license?" with title "Hood Warfare 2" buttons {"Cancel", "Install Rosetta"} default button "Install Rosetta" cancel button "Cancel"
APPLESCRIPT
  /usr/bin/osascript -e 'do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges'
fi

download() {
  local url="$1" expected="$2" target="$cache/$3" actual
  if [[ ! -f "$target" ]]; then
    print -- "Downloading $3…"
    download_part="$(mktemp "$target.part.XXXXXX")"
    /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 --connect-timeout 30 --output "$download_part" "$url"
    actual="$(/usr/bin/shasum -a 256 "$download_part")"; actual="${actual%% *}"
    [[ "$actual" == "$expected" ]] || { hood_fail "Download verification failed for $3. Upstream may have changed; check the repository for an updated installer."; return 1; }
    mv "$download_part" "$target"
    download_part=''
  fi
  actual="$(/usr/bin/shasum -a 256 "$target")"; actual="${actual%% *}"
  [[ "$actual" == "$expected" ]] || { hood_fail "Cached $3 does not match its pinned SHA-256. Remove that cached file and retry."; return 1; }
}
download "$TEMPLATE_URL" "$TEMPLATE_SHA" Template-1.0.21.tar.xz
download "$ENGINE_URL" "$ENGINE_SHA" WS12WineSikarugir11.0_1.tar.xz
download "$STEAM_URL" "$STEAM_SHA" SteamSetup.exe
download "$VC_URL" "$VC_SHA" VC_redist.x64.exe

if [[ ! -d "$HOOD_APP" ]]; then
  print -- 'Building the app from the verified, empty upstream template…'
  stage="$(mktemp -d "$HOOD_ROOT/.assemble.XXXXXX")"
  /usr/bin/tar -xJf "$cache/Template-1.0.21.tar.xz" -C "$stage"
  /usr/bin/tar -xJf "$cache/WS12WineSikarugir11.0_1.tar.xz" -C "$stage"
  [[ -d "$stage/Template-1.0.21.app/Contents" && -d "$stage/wswine.bundle/bin" ]] || { hood_fail 'Unexpected upstream archive layout.'; exit 1; }
  mv "$stage/wswine.bundle" "$stage/Template-1.0.21.app/Contents/SharedSupport/wine"
  mv "$stage/Template-1.0.21.app" "$HOOD_APP"
  /usr/bin/xattr -dr com.apple.quarantine "$HOOD_APP" 2>/dev/null || true
fi
hood_owned
hood_plist CFBundleIdentifier string 'studio.spacemates.hoodwarfare2'
hood_plist CFBundleName string 'Hood Warfare 2'
hood_plist CFBundleDisplayName string 'Hood Warfare 2'
/usr/libexec/PlistBuddy -c 'Delete :NSBGOnly' "$HOOD_PLIST" 2>/dev/null || true
hood_plist D3DMETAL integer 1
hood_plist DXVK integer 0
hood_plist DXMT integer 0
hood_plist 'Skip Gecko' integer 1
hood_plist 'Skip Mono' integer 1
hood_plist 'Symlinks In User Folder' integer 0
hood_plist WINEDEBUG string '-all'
hood_plist 'Program Name and Path' string '/Program Files (x86)/Steam/Steam.exe'
if [[ ! -f "$HOOD_ROOT/.setup-complete" ]]; then hood_plist 'Program Flags' string 'steam://install/5155360'; fi

for tool in common.zsh layout.zsh play.zsh steam.zsh quit.zsh controller-test.zsh finish.zsh steam-options.pl; do
  cp "$script_dir/$tool" "$HOOD_TOOLS/$tool"
done
make_shortcut() {
  local name="$1" target="$2"
  {
    print -r -- '#!/bin/zsh'
    print -r -- 'set -eu'
    print -r -- "exec /bin/zsh \"\${0:A:h}/Tools/$target\" \"\$@\""
  } > "$HOOD_ROOT/$name.command"
  chmod +x "$HOOD_ROOT/$name.command"
}
make_shortcut 'Play Hood Warfare 2' play.zsh
make_shortcut 'Open Windows Steam' steam.zsh
make_shortcut 'Quit Windows Steam' quit.zsh
make_shortcut 'Controller Layout' layout.zsh
make_shortcut 'Test Controller' controller-test.zsh
make_shortcut 'Finish Setup' finish.zsh
if [[ -n "$layout" ]]; then
  /bin/zsh "$HOOD_TOOLS/layout.zsh" "$layout"
elif [[ ! -f "$HOOD_ROOT/controller-layout" ]]; then
  /bin/zsh "$HOOD_TOOLS/layout.zsh"
  # Cancelling the optional chooser keeps the standard positional layout.
  [[ -f "$HOOD_ROOT/controller-layout" ]] || /bin/zsh "$HOOD_TOOLS/layout.zsh" positions
fi
/usr/bin/plutil -lint "$HOOD_PLIST" >/dev/null
if (( prepare_only )); then
  print -- "App assembled at $HOOD_ROOT. Prerequisites and Steam have not been installed."
  exit 0
fi

hood_runtime
if [[ ! -f "$HOOD_PREFIX/system.reg" ]]; then
  print -- 'Initializing a new Windows environment…'
  "$WINE" wineboot -u >>"$HOOD_LOGS/setup.log" 2>&1
  # This engine can return before wineserver flushes its initial registry files.
  for attempt in {1..30}; do
    [[ ! -f "$HOOD_PREFIX/system.reg" ]] || break
    sleep 1
  done
fi
[[ -f "$HOOD_PREFIX/system.reg" ]] || { hood_fail "Wine initialization failed. See $HOOD_LOGS/setup.log"; exit 1; }
if [[ ! -f "$HOOD_ROOT/.vc-ready" ]]; then
  print -- 'Installing Microsoft Visual C++ x64…'
  vc_result=0
  "$WINE" "$cache/VC_redist.x64.exe" /install /quiet /norestart >>"$HOOD_LOGS/setup.log" 2>&1 || vc_result=$?
  # Windows success-with-reboot (3010) is truncated to 194 by a POSIX shell.
  (( vc_result == 0 || vc_result == 194 )) || { hood_fail "Visual C++ installation failed ($vc_result). See Logs/setup.log."; exit 1; }
  print -- '1' > "$HOOD_ROOT/.vc-ready"
fi
if [[ ! -f "$HOOD_STEAM/Steam.exe" ]]; then
  print -- 'Installing Windows Steam…'
  "$WINE" "$cache/SteamSetup.exe" /S >>"$HOOD_LOGS/setup.log" 2>&1
fi
[[ -f "$HOOD_STEAM/Steam.exe" ]] || { hood_fail 'Steam installation did not finish. Run the installer again.'; exit 1; }
# CRLF batch file: preserve Steam launch tracking while skipping only the faulty UE prerequisite bootstrap.
{
  print -r -- '@echo off'
  print -r -- 'setlocal'
  print -r -- 'cd /d "C:\Program Files (x86)\Steam\steamapps\common\Hood Warfare 2"'
  print -r -- 'if errorlevel 1 exit /b %errorlevel%'
  print -r -- '"HW2\Binaries\Win64\HW2-HoodWarfare2-Win64-Shipping.exe" HW2 -windowed -ResX=1280 -ResY=720'
  print -r -- 'exit /b %errorlevel%'
} | /usr/bin/perl -pe 's/\n/\r\n/g' > "$HOOD_PREFIX/drive_c/HoodWarfare2-launch.cmd"
print -- '1' > "$HOOD_ROOT/.components-ready"
print -- "Setup files are ready in $HOOD_ROOT"
if (( no_open )); then
  print -- 'Run Finish Setup.command to sign in and download your game.'
else
  # Keep the same lock/PID across exec, including the Steam download and repair.
  hood_cleanup_stage
  exec /bin/zsh "$HOOD_TOOLS/finish.zsh"
fi
