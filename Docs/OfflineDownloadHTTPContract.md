# Offline-download HTTP contract

The first implementation stage verifies the assumptions that make durable
offline downloads possible. The application must not append bytes to a partial
file unless every check below succeeds.

## Required responses

| Request | Required response |
| --- | --- |
| Initial `HEAD` or `GET` | `200`, exact `Content-Length`, `Accept-Ranges: bytes`, strong `ETag` |
| Resume with `Range: bytes=N-` and the stored `If-Range` ETag | `206`, matching `ETag`, exact `Content-Range` and remaining `Content-Length` |
| Resume with a mismatched `If-Range` ETag | `200`; the partial file must not be appended to |
| Range beginning at the file length | `416` |

The expected total length comes from `NativeTorrentFile.length`. The stored
identity consists of that length and the strong ETag returned by TorrServer.

## Verified bundled engine

On 2026-09-09, the packaged `TorrServer-darwin-arm64` reported
`MatriX.144.1`. A live probe against an isolated read-only copy of the app's
TorrServer database confirmed all four response cases above. A 16-byte `GET`
also returned `206` and exactly 16 bytes.

Run the contract probe again whenever the bundled TorrServer version changes:

```bash
scripts/verify-offline-download-contract.sh '<stream-url>' '<expected-file-size>'
```

The URL must be the same `/stream/<name>?link=<hash>&index=<id>&play` URL that
the application uses for playback. The probe requests at most 16 body bytes,
but TorrServer currently records every stream request as viewed.

## Implementation rule

`OfflineDownloadHTTPContract` is the single validator for initial and resumed
responses. A future download manager must truncate/restart or ask the user when
the server returns `200` to a resume request. It must never append that response
to an existing partial file.
