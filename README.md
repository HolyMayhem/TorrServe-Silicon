<p align="center">
  <img src="Docs/assets/app-icon.png" width="128" height="128" alt="TorrServe Silicon">
</p>

<h1 align="center">TorrServe Silicon</h1>

<p align="center">
  <strong>A native TorrServer app for macOS</strong><br>
  Your media library, torrent search, and playback launching — in one app.
</p>

<p align="center">
  <a href="https://github.com/HolyMayhem/TorrServe-Silicon/releases/latest">Download for macOS</a>
  &nbsp;·&nbsp;
  <a href="https://youtu.be/TmBXq8BSu-8">Watch the demo</a>
  &nbsp;·&nbsp;
  <strong>English</strong> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-343434?style=flat-square" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-77B900?style=flat-square" alt="Apple Silicon · arm64">
  <img src="https://img.shields.io/badge/TorrServer-included-77B900?style=flat-square" alt="TorrServer included">
</p>

---

Add a magnet link or a `.torrent` file. TorrServe Silicon identifies the movie or series, loads its poster, description, and ratings, and lets you launch playback with **Watch**.

Manage TorrServer and your library from the app without constantly switching to Terminal or the TorrServer Web UI.

## See it in action

<p align="center">
  <a href="https://youtu.be/TmBXq8BSu-8">
    <img src="https://img.youtube.com/vi/TmBXq8BSu-8/hqdefault.jpg" width="640" alt="Watch the TorrServe Silicon video on YouTube">
  </a>
</p>

<p align="center">
  <a href="https://youtu.be/TmBXq8BSu-8"><strong>▶ Watch on YouTube</strong></a>
</p>

## Features

| | What you can do |
| --- | --- |
| **TorrServer built in** | Start and manage the server directly from the app or the macOS menu bar. |
| **Visual media library** | Add magnet links and `.torrent` files, then browse your library with posters. |
| **Smart metadata** | Automatically identify movies, series, and anime; load descriptions, genres, year, and ratings. |
| **Torrent search** | Find and add torrents inside the app through an optional Jackett connection. |
| **Your preferred player** | Launch playback in QuickTime, IINA, VLC, or Infuse. |
| **Two interface languages** | Use the app in English or Russian. |

## Installation

**Requires macOS 15 or later and a Mac with Apple Silicon.** An internet connection is needed.

1. Download the latest `TorrServer-*-macOS-arm64.dmg` from [Releases](https://github.com/HolyMayhem/TorrServe-Silicon/releases/latest).
2. Open the DMG and drag **TorrServe Silicon** into **Applications**.
3. Launch the app.

TorrServer is already included; there is no separate server installation.

> [!NOTE]
> If macOS blocks the first launch, open **System Settings → Privacy & Security** and allow the app to run.

On macOS 26, the app uses native **Liquid Glass**.

## Smart metadata

A torrent name such as `Interstellar.2014.2160p.UHD.BluRay.REMUX` can become a movie card with a poster, title, description, genres, and rating.

Metadata lookup uses **TMDB · OMDb · Kinopoisk · AniList**. If one source does not find a match, the app can try the next one. AniList supports anime lookup.

English descriptions can be translated into Russian with system **Apple Translation** when needed.

## Search through Jackett

Connect a configured [Jackett](https://github.com/Jackett/Jackett) instance to search torrents directly inside the app:

**Find a movie → choose a torrent → add it → start watching.**

Jackett is optional. The media library, TorrServer, and metadata features also work without it.

## Acknowledgements

TorrServe Silicon is an independent app for working with [YouROK/TorrServer](https://github.com/YouROK/TorrServer).

TorrServer and the third-party services used by the app are separate projects distributed under their own terms and licenses.
