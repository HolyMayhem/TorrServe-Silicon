# Releasing TorrServe Silicon

TorrServe Silicon uses Sparkle 2 with EdDSA-signed updates. Release builds are
ad-hoc signed because this project does not use the paid Apple Developer
Program. Users may still need to approve the first manually installed build in
macOS Privacy & Security.

## One-time setup

Resolve the Swift package and generate the signing key:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.holymayhem.torrserve-silicon-updates
```

The private key stays in the macOS login Keychain. Only the public key belongs
in `Resources/Info.plist`. Export and protect an offline backup of the private
key; never commit it to Git or attach it to a GitHub release.

```bash
umask 077
mkdir -p .release-secrets
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.holymayhem.torrserve-silicon-updates \
  -x .release-secrets/sparkle-private-key
```

Copy that file to encrypted offline storage. The local `.release-secrets`
directory is ignored by Git, but it is not a substitute for a separate backup.

## Bridge release 2.7.0

Version 2.7.0 is the first build that contains Sparkle. Existing users must
install this version manually once. Automatic in-app updates start with the
next release (2.7.1 or newer).

Make sure the empty `appcast.xml` from this repository is already available on
the `main` branch before publishing 2.7.0, so a manual check never receives a
404 response.

## Prepare a release

1. Set an incremented `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Run the available checks and build the app.
3. Prepare the exact DMG and matching appcast:

```bash
RELEASE_NOTES_FILE=/absolute/path/to/release-notes.md \
  ./scripts/prepare-sparkle-release.sh
```

The script verifies that the Keychain key matches the public key embedded in
the app, creates the DMG, signs the update with EdDSA, embeds the supplied
release notes in the feed, and writes `appcast.xml`.

## Publish safely

1. Create the Git tag printed by the script.
2. Create a draft GitHub Release for that tag.
3. Upload the exact DMG from `dist/`; do not rebuild it after generating the
   appcast.
4. Publish the GitHub Release.
5. Commit and push the generated `appcast.xml` last, after the DMG URL works.

Publishing the appcast last prevents installed applications from seeing an
update whose archive is not available yet.
