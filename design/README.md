# Inlaut brand integration

The current master is **Sprachimpuls / Petrol & Mint** in [`inlaut-brand-kit/`](inlaut-brand-kit/README.txt), supplied as `inlaut-brand-kit.zip`. The original kit is kept unchanged. Its [`Brand-Guide.html`](inlaut-brand-kit/Brand-Guide.html) shows the palette and vector masters.

## App

- `python3 scripts/sync-brand.py` installs the supplied web assets, adaptive Xcode colour sets, wordmark and symbol templates. Run from the repository root on macOS with Xcode installed.
- `Resources/Inlaut.icon` uses a full-bleed petrol background and the kit's unmasked mint waveform. `scripts/outline-brand.swift` outlines the exact stroked vector using CoreGraphics before Icon Composer applies materials; otherwise a material fill closes the open waveform. Xcode applies the platform mask and native glass. Dark and tinted appearances are included.
- The menu glyph stays a system-tinted template. Ready uses the supplied 18 pt glyph. Preparing, recording, transcribing and failure add distinct monochrome badges, preserving state information without relying on colour.
- Setup and Settings use the vector wordmark, system typography and porcelain/night surfaces. The recording pill keeps its native glass, level meter, system accessibility fallbacks and physical-screen positioning, with an explicit “Hört zu” status.
- Build with `xcodegen generate` and the Xcode commands in the main README.

## Website

`site/public/` stays a static, script-free website with no remote fonts or embedded third-party assets. It follows the system appearance, includes a responsive illustrative dictation view, keyboard focus/skip navigation and reduced-motion support. The download button points to the versioned GitHub DMG; publish the DMG and Sparkle ZIP before deploying the website and signed update feed.

## Installer

`scripts/render-dmg-background.swift` generates the porcelain/petrol installer background from the supplied wordmark at 1x and 2x. AppKit derives the Retina scale from `NSBitmapImageRep.size`; do not apply a second graphics-context scale. `scripts/dmg-settings.py` positions the native app icon and a “Programme” link to `/Applications` on either side of the arrow. The generated artwork and DMG stay in `build/release/`; `scripts/release.sh dmg` builds and notarizes the image. The app inside is unchanged.

[`social-card.html`](social-card.html) is the source for the social sharing image. Serve `design/` locally, open this page at 1200 × 630 CSS pixels and export a browser screenshot. The current preview export is 1280 × 672 pixels; the Open Graph dimensions match that file. The checked-in social image includes the kit's supplied static glass icon; the native app uses Icon Composer's rendering.

## Archived material

`build-support/`, `directions-v1/` and `chatgpt-prompt.md` document the previous Setzpunkt direction. They are not the current asset pipeline. Existing Manrope files are historical; the current website does not load them.

The previous asset licensing policy is retained in [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md); the new kit does not introduce a different licence.
