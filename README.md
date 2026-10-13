# Hood Warfare 2 on Mac

Run the Windows Steam version of Hood Warfare 2 on an Apple Silicon Mac using Wine and D3DMetal. No Homebrew or paid compatibility software required. You must own the game on Steam.

## Install

1. [Download the ZIP](https://github.com/SPACEMATES-STUDIO/hood-warfare-2-on-mac/releases/latest/download/Hood-Warfare-2-on-Mac.zip), unzip it, and open `Install.command`.
2. Choose controller button positions, Nintendo button letters, or keyboard and mouse.
3. Sign in privately to Windows Steam and download Hood Warfare 2.
4. Setup finishes and opens the game. Next time, open `Hood Warfare 2.app`.

If interrupted, resume with `Finish Setup.command` in the installation folder.

Requires Apple Silicon, macOS 15+, Rosetta 2, and at least 25 GB free. 16 GB RAM is recommended. Installation lives in `~/Applications/Hood Warfare 2 on Mac`.

Public multiplayer, movement, and firing worked on M4 Pro/macOS 27.0.1 with game build 25888787. Installer tested through Steam sign-in; controller gameplay unverified.

Use `Controller Layout.command` to change button preference, `Test Controller.command` to check input, or `Open Windows Steam.command` to manage Steam.

When done, close the game, then open `Quit Windows Steam.command`. Closing a Steam window alone can leave Steam running.

[Troubleshooting](docs/TROUBLESHOOTING.md) · [Technical details](docs/TECHNICAL.md) · [Third-party software](THIRD-PARTY.md)

Project scripts are MIT licensed. Downloaded components retain their own licenses.
