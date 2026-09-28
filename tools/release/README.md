# Releasing Grove

Updates ship through Sparkle. The app reads `https://houwert.dev/grove/updates/appcast.xml`, and a houwert.dev function serves the appcast and archives from this private repo's GitHub Releases, the same way Argus is served.

## Cutting a release

Run the **Release** workflow on `main` with a version (`0.2.0`) and a channel:

- `beta` tags `v0.2.0-beta.N`, marks the GitHub release as a pre-release and adds a beta item to the appcast. Only clients with "Receive beta updates" on (Preferences > General) see it.
- `production` tags `v0.2.0`; every client sees it.

The workflow signs with the shared `match` Developer ID cert, notarizes with the App Store Connect key, then `package.sh` builds the zip and DMG and appends to the appcast carried over from the previous release.

Locally: `bundle exec fastlane mac release version:0.2.0 channel:beta`, then publish `dist/` by hand.

## Secrets

The same as Argus (`MATCH_GIT_URL`, `MATCH_GIT_PAT`, `MATCH_PASSWORD`, `MATCH_KEYCHAIN_PASSWORD`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT`), plus `SPARKLE_PRIVATE_KEY`:

```sh
app/Grove/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account grove -x /tmp/grove.key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/grove.key && rm /tmp/grove.key
```

The public half is `SUPublicEDKey` in `app/Grove/Grove/Info.plist`. Losing the private key means shipped builds can't verify new updates.
