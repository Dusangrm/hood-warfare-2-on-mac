# Third-party software

This repository's scripts and documentation are MIT licensed. That license does not cover software downloaded by the installer or the game.

The release ZIP contains this project's setup files. It does not contain Wine runtime archives, Apple's libraries, Microsoft redistributables, Steam, game files, a Wine prefix, or account data. The installer downloads dependencies from their upstream publishers and preserves their included notices and license files.

| Component | Publisher / source | License information |
| --- | --- | --- |
| Sikarugir launcher, template, and packaged Wine engine | [Sikarugir project](https://github.com/Sikarugir-App/Sikarugir), [engine releases](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0), [template releases](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) | Components have different upstream terms. See the project's licensing notes and the notices in the downloaded packages. |
| Wine | [Wine project](https://www.winehq.org/) | LGPL-2.1-or-later; consult the packaged components and upstream source for their notices. |
| SDL and SDL2 compatibility layer | [SDL](https://github.com/libsdl-org/SDL), [sdl2-compat](https://github.com/libsdl-org/sdl2-compat) | zlib license. |
| D3DMetal evaluation libraries | [Apple Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) | Apple's separate license applies. The downloaded template includes the D3DMetal README, license, and acknowledgements. |
| Microsoft Visual C++ Redistributable | [Microsoft's official downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170) | Microsoft's software license terms apply. Downloaded directly from Microsoft. |
| Steam client | [Valve's official download](https://store.steampowered.com/about/) | Valve's terms apply; users sign in through Steam themselves. |
| Hood Warfare 2 | [Steam store page](https://store.steampowered.com/app/5155360/Hood_Warfare_2/) | Separately purchased by the user and installed through Steam. No game assets are distributed by this project. |

The Sikarugir template also includes DXMT and other support libraries with their own upstream notices. Preserve those notices when installing or maintaining the downloaded runtime. This community setup is not affiliated with the game developer, Valve, Apple, Microsoft, or the Sikarugir project.
