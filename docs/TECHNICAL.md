# Technical details

## What was verified

The original setup ran Steam app `5155360`, public game build `25888787`, on an Apple M4 Pro Mac with macOS 27.0.1. A populated public Turf War match verified joining, spawning, movement, firing, and changing player scores.

A subsequent restart through the saved launcher and Steam launch option reached the menu without the prerequisite dialog, listed public servers, and joined another populated match.

The portable installer's VDF configuration and lifecycle checks passed. A separate clean destination was assembled from the pinned archives, initialized with a fresh Wine prefix, and successfully installed Microsoft Visual C++ and Windows Steam. The native Steam-only launcher reached a visually verified, fully rendered sign-in screen with username/password fields and a QR code. No account was signed in during that test, and the existing working game setup was left untouched.

Installer validation therefore covers setup through Steam sign-in. A fresh game download and multiplayer test in the new prefix were not repeated; the multiplayer evidence above comes from the original setup.

Nintendo Switch Pro hardware was detected as an XInput controller. A persistent Nintendo button-letter preference was configured, but physical-button and in-game controller testing have not yet been completed.

## Installation architecture

`Install.command` uses zsh and tools included with macOS. It requires Apple Silicon, macOS 15 or newer, Rosetta 2, and at least 25 GB free. 16 GB RAM is recommended, not enforced.

The destination is `~/Applications/Hood Warfare 2 on Mac`. Upstream runtime archives are downloaded, checked against pinned SHA-256 hashes, and assembled into a dedicated application. A fresh Wine prefix is created for each new installation; no existing prefix or Steam account is distributed.

The template archive contains `Template-1.0.21.app` with its native launcher, libraries, and renderers. It contains neither an engine nor a prefix. The engine archive's `wswine.bundle` becomes `Contents/SharedSupport/wine`. The new prefix lives at `Contents/SharedSupport/prefix`. The template's `Contents/drive_c` symlink points into that prefix.

The template declares macOS 14.6 as its minimum, but its bundled D3DMetal 4.0b2 README requires Apple Silicon and macOS 15 or newer. The installer follows the renderer's requirement.

## Pinned downloads

Each component is fetched from its publisher. Nothing in this table is included in the project's release ZIP.

| Component | Version / file | SHA-256 |
| --- | --- | --- |
| Sikarugir engine | `WS12WineSikarugir11.0_1.tar.xz` | `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e` |
| Sikarugir template | `Template-1.0.21.tar.xz` | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| Windows Steam installer | `SteamSetup.exe` | `7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb` |
| Microsoft Visual C++ x64 | `14.51.36247.0` | `843068991daaa1f73ad9f6239bce4d0f6a07a51f18c37ea2a867e9beca71295c` |

Download URLs:

- [Sikarugir engine](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz)
- [Sikarugir template](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz)
- [Windows Steam installer](https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe)
- [Microsoft Visual C++ x64 14.51.36247.0](https://download.visualstudio.microsoft.com/download/pr/ebdab8e5-1d7b-4d9f-a11b-cbb1720c3b12/843068991DAAA1F73AD9F6239BCE4D0F6A07A51F18C37EA2A867E9BECA71295C/VC_redist.x64.exe)

Steam's installer URL can change content. A checksum mismatch must stop installation until the new upstream artifact is reviewed and the pin updated.

## Runtime configuration

The setup enables D3DMetal and makes DXMT available for Steam's rendering path. It preserves the template's dependency libraries and uses the engine marker `SikarugirAppWine11=1`. The marker and `DYLD_FALLBACK_LIBRARY_PATH` are required by this engine outside its native launcher.

Environment paths are derived from the installation directory. Relevant variables include `WINEPREFIX`, `WINEDLLPATH_DXMT`, `WINEDLLPATH_D3DMETAL`, and the D3DMetal library paths. The application uses the included Windows Steam client with ordinary rendering defaults.

## Steam and game launch

The template's `wineskinlauncher` alias selects its native launcher's legacy command-line syntax. To open Steam without the configured game flags, pass the executable path directly:

```text
launcher 'C:\Program Files (x86)\Steam\Steam.exe'
```

Do not insert a `run` subcommand. During initial installation, the app's `Program Flags` contain `steam://install/5155360` to open the game's Steam installation flow. After setup, they become `-applaunch 5155360 -windowed -ResX=1280 -ResY=720`.

Users sign in privately and download their purchased game through Steam. Setup automatically proceeds to its finishing step and opens the game. `Finish Setup.command` resumes this step if interrupted. It waits for the game manifest and executable, closes this installation's Steam client, backs up its local configuration, and changes only app `5155360`'s launch option:

```text
C:\windows\system32\cmd.exe /d /c C:\HoodWarfare2-launch.cmd %command%
```

The generated batch file changes to Steam's installed game directory and runs:

```text
"HW2\Binaries\Win64\HW2-HoodWarfare2-Win64-Shipping.exe" HW2 -windowed -ResX=1280 -ResY=720
```

It waits normally and returns the executable's exit code. It ignores the appended original bootstrap command. Steam tracks the resulting processes under the game's app ID. The workaround addresses a false Visual C++ prerequisite check in `HW2.exe`; the original game and anti-cheat binaries remain unchanged.

## Quitting

`Quit Windows Steam.command` shares setup's operation lock and refuses to interrupt an active installation or running game. It requests `Steam.exe -shutdown`, waits for Steam to exit, and only then stops that prefix's Wine helpers. A timeout or invalid process listing fails without forcing Steam or the game to quit. Setup releases its lock before launching the finished game.

Shutdown first checks `wineserver -k0` with this installation's explicit `WINEPREFIX`, and repeats that check before polling with `tasklist`. Signal 0 checks an existing server without starting one; when it reports a stopped session, no Wine command follows. The probe and listing are not atomic: Wine can exit between them, so a later `tasklist` could briefly restart Wine services. It does not open Steam, and the shutdown flow closes those helpers. See Wine 11's [option handling](https://github.com/wine-mirror/wine/blob/wine-11.0/server/main.c#L79-L84) and [server-lock probe](https://github.com/wine-mirror/wine/blob/wine-11.0/server/request.c#L718-L760).

The installer adds no login item or background relaunch service. Steam may recreate its webhelper window while its main process remains alive, so closing a Wine window is not a reliable way to exit Steam.

## Controller preference

Controller setup uses Wine's generic SDL/XInput path, with no device-specific allowlist or hard-coded hardware ID. Standard positions are the default for a fresh install; the saved choice is a button-mapping preference, not a controller-brand selector. The bundled SDL2 compatibility library uses SDL3. `SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1` requests printed button letters on supported devices; `0` requests positional face-button mapping. The preference is scoped to this installation.

The tester uses Wine's `control.exe joy.cpl`. Its diagram does not redraw to match the controller or selected layout; verify reported button presses instead. [SDL's button-label documentation](https://wiki.libsdl.org/SDL2/SDL_HINT_GAMECONTROLLER_USE_BUTTON_LABELS) describes the distinction. Device detection and gameplay need hardware testing; the implementation does not establish compatibility with every controller model.
