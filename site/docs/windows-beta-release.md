# Windows beta website preparation

Status: staged only, not deployed. The maintainer chose to wait for signing before enabling a Windows download.

The German and English sites link to `/windows` and `/en/windows`. Their Windows-logo buttons lead to release information; the installer buttons are disabled and there is no EXE URL or Windows download event. Existing macOS downloads remain active.

Before publishing the signed beta:

1. Complete SignPath onboarding and the signing workflow in `windows/signing/README.md`.
2. Verify the signed installer and a signed upgrade on a Windows device. Confirm the supported systems and known limitations against the actual release.
3. Publish an explicitly marked GitHub prerelease (do not replace the latest stable macOS release). Upload the signed EXE and checksums, then verify the public asset URLs.
4. Replace the disabled installer buttons on both Windows pages with links to that exact signed release asset, add `data-umami-event="download-windows"` and the released version, and show version/requirements. Keep the Beta label.
5. Update the pending-release wording across both languages, including home-page availability/FAQ, comparison pages, business and privacy information, `llms.txt`, and this status. Keep Mac-only features scoped to macOS; Windows currently recognises German only. Regenerate home-page FAQ JSON-LD with `python3 scripts/sync-faq-schema.py`.
6. Recheck links and desktop/mobile layouts, then deploy with `cd site && npx wrangler deploy`. Verify both live languages and the downloads. Publish any update feed only after its signed assets are available.

This preparation also preserves the existing local website additions (analytics event positions and the legal/healthcare and Superwhisper pages). The source checkout remains untouched; this branch is an isolated integration snapshot.
