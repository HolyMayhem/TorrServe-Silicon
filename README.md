# TorrServe Silicon

**English** | [Русский](README.ru.md)

**A native TorrServer app for macOS.**

TorrServe Silicon brings TorrServer, a media library, torrent search, metadata,
and playback launching into one app.

Add a torrent -> the app detects the movie or series -> loads the poster,
description, and ratings -> press **Watch**.

No constant Terminal or TorrServer Web UI work required.

---

## Features

- start and manage **TorrServer** directly from the app;
- add **magnet links** and **`.torrent` files**;
- use a media library with posters instead of a plain torrent list;
- automatically identify movies, series, and anime;
- fetch descriptions, genres, year, ratings, and other metadata;
- search torrents through **Jackett**;
- start playback in **QuickTime, IINA, VLC, or Infuse**;
- control TorrServer from the **macOS menu bar**;
- use the interface in Russian or English.

---

## Smart metadata

TorrServe Silicon analyzes torrent names and tries to detect their content
automatically.

For example:

`Interstellar.2014.2160p.UHD.BluRay.REMUX`

becomes a full movie card with a poster, title, description, genres, and rating.

Metadata lookup uses:

**TMDB · OMDb · Kinopoisk · AniList**

If one source does not find a match, the app can try the next one.

**AniList** is supported for anime.

English descriptions can be translated into Russian with system
**Apple Translation** when needed.

---

## Search through Jackett

If you have [Jackett](https://github.com/Jackett/Jackett) configured, you can
search torrents directly inside the app:

**find a movie -> choose a torrent -> add it -> start watching.**

Jackett is optional. Without it, the media library, TorrServer, and metadata
features continue to work.

---

## Installation

1. Open [Releases](https://github.com/HolyMayhem/TorrServe-Silicon/releases).
2. Download the latest `TorrServer-*-macOS-arm64.dmg`.
3. Open the DMG.
4. Drag TorrServe Silicon into **Applications**.
5. Launch the app.

**TorrServer is already included in the app and does not need to be installed
separately.**

> [!NOTE]
> If macOS blocks the first launch, open
> **System Settings -> Privacy & Security**
> and allow the app to run.

---

## Requirements

- **macOS 15 or later**
- **Mac with Apple Silicon**
- internet connection

On macOS 26, the app uses native **Liquid Glass**.

---

## Acknowledgements

TorrServe Silicon is an independent app for working with
[YouROK/TorrServer](https://github.com/YouROK/TorrServer).

TorrServer and the third-party services used by the app are separate projects
distributed under their own terms and licenses.
