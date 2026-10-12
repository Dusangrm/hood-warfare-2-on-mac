#!/bin/zsh
set -eu
source "${0:A:h}/common.zsh"
hood_paths "${0:A:h:h}"
hood_owned
layout="${1:-}"
if [[ -z "$layout" ]]; then
  choice=$(/usr/bin/osascript <<'APPLESCRIPT'
set answer to choose from list {"Standard positions (Xbox / PlayStation / most controllers)", "Nintendo letters (X top, A right, B bottom, Y left)", "Keyboard and mouse"} with title "Hood Warfare 2 — Controls" with prompt "Choose how the game should read your buttons." default items {"Standard positions (Xbox / PlayStation / most controllers)"} OK button name "Save"
if answer is false then return "cancel"
return item 1 of answer
APPLESCRIPT
  )
  case "$choice" in
    Standard*) layout=positions ;;
    Nintendo*) layout=labels ;;
    Keyboard*) layout=keyboard ;;
    *) exit 0 ;;
  esac
fi
case "$layout" in positions|labels|keyboard) ;; *) hood_fail 'Choose positions, labels, or keyboard.'; exit 1 ;; esac
print -r -- "$layout" > "$HOOD_ROOT/controller-layout.tmp"
mv "$HOOD_ROOT/controller-layout.tmp" "$HOOD_ROOT/controller-layout"
hood_layout_env
# Finder needs LSEnvironment; direct command launches export the same preference.
/usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict' "$HOOD_PLIST" 2>/dev/null || true
hood_plist 'LSEnvironment:SDL_GAMECONTROLLER_USE_BUTTON_LABELS' string "$SDL_GAMECONTROLLER_USE_BUTTON_LABELS"
hood_plist 'CLI Custom Commands' string "export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=$SDL_GAMECONTROLLER_USE_BUTTON_LABELS"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOOD_APP" >/dev/null 2>&1 || true
print -- "Saved: $layout. Close the game and this Windows Steam client before reopening the game."
print -- 'The Windows test illustration stays Xbox-shaped; check which letter lights up.'
