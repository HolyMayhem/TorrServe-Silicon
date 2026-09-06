# TorrServer for macOS

**English** | [Русский](README.ru.md)

A native SwiftUI controller for TorrServer on Apple Silicon Macs. It combines
server management, torrent search, a media library, metadata, playback, and
menu bar controls in one macOS app—without requiring Terminal or the standard
TorrServer Web UI for everyday use.

The interface follows modern macOS conventions and uses native Liquid Glass on
macOS 26, with compatible system materials on earlier supported versions.

## Highlights

- Start, stop, update, configure, and diagnose TorrServer.
- Add magnet links and `.torrent` files directly to the library.
- Browse the library in compact list, poster grid, or detailed card layouts.
- Search public indexers through an optional Jackett connection.
- Fetch posters, descriptions, genres, release dates, runtimes, and ratings
  from TMDB, OMDb, Kinopoisk, and AniList.
- Configure metadata lookup order and use built-in or custom API keys.
- Translate English descriptions into Russian with Apple Translation.
- Play media in QuickTime Player, IINA, VLC, Infuse, or the default macOS app.
- Monitor TorrServer from the menu bar, including live stream speed, recent
  material, quick actions, and a local Web UI QR code.
- Reorder menu bar sections with drag and drop.
- Use the complete interface in English or Russian.

## Server management

The Apple Silicon `TorrServer-darwin-arm64` executable is bundled into the app
during packaging. The Server Settings screen provides:

- editable executable and storage paths;
- memory and disk cache controls;
- TorrServer update checks;
- storage information and cache cleanup;
- diagnostics for the executable, port, API, Web UI, storage, and players.

The Web UI remains available from the app whenever direct access is useful.

## Installation

1. Download the latest `TorrServer-*-macOS-arm64.dmg` from
   [Releases](https://github.com/HolyMayhem/TorrServe-Silicon/releases).
2. Open the DMG.
3. Drag `TorrServer.app` into `Applications`.
4. Launch the app and select a preferred playback application.

If macOS blocks the first launch of a non-notarized build, Control-click the
app and choose **Open**, or allow it in **System Settings → Privacy & Security**.

## Optional integrations

### Jackett

[Jackett](https://github.com/Jackett/Jackett) is required only for the Search
section. Configure its address and API key in General Settings. The library,
server controls, and playback work without Jackett.

### Metadata providers

Metadata is optional. Select a provider in General Settings and use either the
keys bundled by the build or your own API keys. Available providers are TMDB,
OMDb, Kinopoisk, and AniList for anime matching.

### External players

QuickTime Player works without additional installation. IINA, VLC, and Infuse
must be installed separately before they can be selected.

## Requirements

- macOS 15 or later.
- A Mac with Apple Silicon.
- Network access to TorrServer and any enabled search or metadata services.

## Build from source

Building the distributable app requires the current Xcode toolchain with Icon
Composer support.

```bash
git clone https://github.com/HolyMayhem/TorrServe-Silicon.git
cd TorrServe-Silicon
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
```

The app is written to `build/app/TorrServer.app`. Unless
`TORRSERVER_EXECUTABLE` points to a local arm64 binary, the build script
downloads the latest TorrServer executable from the upstream
[TorrServer project](https://github.com/YouROK/TorrServer).

## Create a DMG

Before packaging a public build, copy `Config/MetadataKeys.example.plist` to
`Config/MetadataKeys.plist` and fill in the TMDB, OMDb, and Kinopoisk keys. The
local keys file is ignored by Git. DMG packaging stops if any built-in key is
missing or rejected by its metadata provider.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/package-dmg.sh
```

The finished image is written to `dist/TorrServer-<version>-macOS-arm64.dmg`.
Local builds use ad-hoc signing and are not notarized by Apple.

## Project structure

- `Sources/App` — application lifecycle, window, sidebar, and shared state.
- `Sources/Core` — TorrServer API, formatting, presentation, and system helpers.
- `Sources/Features` — Library, Search, Metadata, Server, Settings, and Menu Bar.
- `Tests/TorrServerManagerTests` — service, model, formatting, and preference tests.
- `scripts` — app build, icon compilation, and DMG packaging.

## Acknowledgements

This project is a native macOS controller for
[YouROK/TorrServer](https://github.com/YouROK/TorrServer). TorrServer and all
optional third-party services remain separate projects governed by their own
licenses and terms.
