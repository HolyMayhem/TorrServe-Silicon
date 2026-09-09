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
responses. The download manager must truncate/restart or ask the user when the
server returns `200` to a resume request. It must never append that response to
an existing partial file.

## Stage 2 baseline transfer

`OfflineDownloadManager` implements one non-resumable transfer at a time. It
validates the initial response, writes received chunks directly to
`<filename>.torrserve-part`, publishes byte and fractional progress, and checks
the exact final byte count. Only then does it close and atomically move the
partial file to the requested destination.

Cancellation removes the partial file. Network and filesystem failures retain
a non-empty partial file. The manager never overwrites an existing destination
or partial file.

## Stage 3 pause and in-session resume

`OfflineDownloadManager` now keeps an in-memory checkpoint containing the
request, the strong ETag, and the exact number of bytes written. Pausing closes
and synchronizes the partial file without deleting it. Resuming first verifies
that the partial file still has the checkpoint's exact size, then requests only
the remaining bytes with `Range: bytes=N-` and the original ETag in `If-Range`.

The response is validated before the partial file is opened for appending. A
full `200` response, changed ETag, incorrect `Content-Range`, or incorrect
remaining `Content-Length` therefore fails safely without adding bytes to the
partial file. Cancelling either an active or paused transfer deletes the partial
file.

## Stage 4 restart recovery

`OfflineDownloadCheckpointStore` persists one versioned checkpoint as an atomic
JSON file in:

```text
~/Library/Application Support/TorrServer/OfflineDownloads/checkpoint.json
```

The checkpoint is written after the initial response has established a strong
ETag, and again when a download pauses or fails. On the next manager creation,
the saved request and ETag are restored and the actual `.torrserve-part` size is
used as the resume offset. This reconciles progress written immediately before
an application interruption without rewriting the JSON file for every network
chunk.

Recovery never overwrites an existing destination. A partial file with the
exact final length is moved into place automatically; a stale record for an
already completed destination is cleared. Missing, oversized, conflicting, or
corrupt state is rejected and its manifest is cleared without deleting the
unverified partial or destination file.
