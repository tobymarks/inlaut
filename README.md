# inlaut

A tiny macOS menu bar app for dictation that never leaves your Mac. Hold a key combination, speak, let go — the text appears in whatever text field has the cursor.

- **Local only.** Speech is recognised on this Mac. No account, no cloud, nothing stored.
- **German first.** Uses [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline), a German fine-tune of NVIDIA Parakeet, which handles technical terms and anglicisms far better than the recogniser built into macOS. A 10-second dictation is text in about 0.3 s on an M3.
- **Instant.** The model (≈ 670 MB, downloaded and checksum-verified once on first start) stays loaded, so dictation starts the moment you press the key. That costs about 900 MB of memory; speech recognition does no work while idle and the microphone is only open while you dictate.
- **Replacements.** Fix what the recogniser keeps getting wrong ("Dum" → "DAM").
- **Fallback.** Apple's on-device recogniser (`SpeechAnalyzer`) is prepared independently and used until Parakeet is ready. macOS may need to download its language assets. Selecting Apple releases the Parakeet model from memory once any current dictation finishes.
- **Updates.** Sparkle checks daily for signed releases, with download and installation started by the user. Automatic checks can be disabled in Settings. No dictation data or system profile is sent.

## Design

The app and website use the **Sprachimpuls / Petrol & Mint** brand kit, with native system typography and light/dark appearances. See [design/README.md](design/README.md) for the source assets and reproducible integration.

## Download

[Download inlaut 0.1.1](https://github.com/tobymarks/inlaut/releases/download/v0.1.1/Inlaut-0.1.1.dmg) for Apple Silicon and macOS 26 or later. Open the DMG, drag inlaut onto the “Programme” (Applications) folder, then open inlaut from Applications. You can eject the disk image after copying. Both the app and the DMG are Developer ID signed and notarized by Apple.

Setup downloads the speech model (around 670 MB) and guides you through microphone and Accessibility permissions. [Release notes and checksums](https://github.com/tobymarks/inlaut/releases/tag/v0.1.1).

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/fetch-sherpa-onnx.sh   # pinned, checksum-verified sherpa-onnx C API into Vendor/
xcodegen generate
xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Inlaut.app
```

`project.yml` signs with the maintainer's team; change `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` for your own builds.

## Tests

```bash
xcodegen generate
xcodebuild -project Inlaut.xcodeproj -scheme Inlaut -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
```

Tests use a private pasteboard and simulated input events: no microphone, actual keyboard events, or personal recordings. GitHub Actions builds and tests on an Apple Silicon macOS 26 runner without signing credentials. Real microphone/hotkey behavior still needs a manual check.

## Releases and updates

Debug uses Apple Development signing; Release uses Developer ID with Hardened Runtime and a secure timestamp. Sparkle 2.10.0 is pinned in `project.yml`. Debug builds do not start the updater.

- Packages: public GitHub Releases at `tobymarks/inlaut`.
- Signed version feed: `https://inlaut.de/updates/appcast.xml`, served with the static Cloudflare website.
- Ed25519 signing key: login Keychain, Sparkle account `de.tobymarks.inlaut`. Only the public key is in the project. Keep an encrypted backup of the private key outside this repository; losing it complicates future updates. Sparkle's `generate_keys -x` can export it when needed.
- No release credentials are required for CI. Signing and notarization run on the maintainer's Mac.

One-time notarization setup, **in your own Terminal**:

```bash
xcrun notarytool store-credentials Inlaut \
  --apple-id YOUR_APPLE_ACCOUNT_EMAIL --team-id 7V4K87652E
```

Replace `YOUR_APPLE_ACCOUNT_EMAIL` with the email address of your Apple Developer account (no typographic quotes). Follow the interactive prompts using that account and an app-specific password created at [account.apple.com](https://account.apple.com). Do not put passwords in scripts, shell arguments, issues, or chat. An existing profile can instead be supplied as `NOTARY_PROFILE=profile-name`.

Build and notarize:

```bash
scripts/release.sh prepare    # archive + Developer ID export; verifies nested signatures
scripts/release.sh notarize   # submit to Apple, require Accepted, staple and check Gatekeeper
```

The second step also packages the stapled app, signs the Sparkle ZIP and feed, and builds, signs and notarizes the drag-to-install DMG. The script refuses to package an app without a valid notarization ticket. The pinned Python packaging tools live in `build/dmg-venv/`; they are not included in the app.

- Sparkle ZIP, signed feed and `SHA256SUMS`: `build/release/updates/<version>-<build>/`.
- DMG, separate `.dmg.sha256` checksum and notarization log: `build/release/downloads/<version>-<build>/`.

To add a DMG for an already exported and stapled app, run `scripts/release.sh dmg`. This leaves the existing ZIP and signed feed untouched and refuses to replace a completed DMG. For an **unpublished** app, `scripts/release.sh package` repeats packaging after successful app notarization. Never regenerate or replace a published archive. The DMG is kept outside Sparkle's input directory so it cannot produce a duplicate update entry.

For each release, increase **both** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; Sparkle compares the build number. Add `release-notes/<version>.html` (an HTML fragment, embedded in the signed feed). Build from the exact source commit that the release tag will reference.

Publishing order:

1. Test recording, hold/toggle, 🌐, paste into a native app and a browser, cancel, and Settings on the exported app. For later releases, also test updating from the previous public version using a separate installation.
2. Create a GitHub Release for the matching source tag. Upload `Inlaut-<version>.dmg`, its `.dmg.sha256` file, `Inlaut-<version>.zip` and `SHA256SUMS`. Download both public packages and verify their checksums and notarization. The DMG is the website download; the ZIP is retained for Sparkle updates.
3. Copy the generated `appcast.xml` to `site/public/updates/appcast.xml` **without editing it** (the feed itself is signed). It keeps earlier entries and their version-specific GitHub URLs.
4. Point the download link in `site/public/index.html` at the public DMG, then deploy the site with `cd site && npx wrangler deploy`.
5. Verify the live download link, DMG and feed before announcing the release. The package step produces the signed feed; do not deploy an unsigned template to released clients.

The DMG layout is defined in `scripts/dmg-settings.py`; `scripts/render-dmg-background.swift` renders the brand artwork at 1x and 2x. `scripts/validate-dmg.py` mounts the image read-only and checks the exact app payload, code signature, notarization ticket, `/Applications` link and Finder layout. Visually inspect the mounted image on a Retina display before publishing.

Useful references: [Sparkle setup](https://sparkle-project.org/documentation/), [Sparkle publishing](https://sparkle-project.org/documentation/publishing/), [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [dmgbuild layout settings](https://dmgbuild.readthedocs.io/en/latest/settings.html).

## Permissions

- **Microphone** — asked on the first dictation.
- **Accessibility** — needed to paste into other apps (the text goes on the clipboard, a ⌘V is sent, and your previous clipboard comes back). Without it the text stays on the clipboard for a manual ⌘V.

The global shortcut uses Carbon hot keys and needs no permission.

## spike/

Measurements that led to the engine choice (on technical German, Whisper-turbo-german made the fewest errors but needs ~2 GB and invents text from noise; Parakeet came close at half the memory and speed; Apple's recogniser failed most technical terms and ignores custom vocabulary): Apple `SpeechAnalyzer` against [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline) (sherpa-onnx) and [whisper-large-v3-turbo-german](https://huggingface.co/primeline/whisper-large-v3-turbo-german) (MLX), on the same recordings. `try_parakeet.py` reuses `local_stt.py` from [winidi/dictate](https://github.com/winidi/dictate) (MIT).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). Model and library licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The inlaut name, logo, app icon and menu bar glyphs are not covered by the GPL; see [design/LICENSE-ASSETS.md](design/LICENSE-ASSETS.md).
