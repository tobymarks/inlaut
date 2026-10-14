# Windows updates

The Windows updater is independent of macOS Sparkle. It never uploads audio,
dictation text, device identifiers, settings or crash reports. On first use the
user is asked whether to enable daily checks; the default until that choice is no
network check. Settings can disable checking or restrict offers to stable releases.
Manual checks remain available. A download and installation require a user click.

## Protocol and installation

- HTTPS feeds: `https://inlaut.de/updates/windows-beta.json` and
  `https://inlaut.de/updates/windows-stable.json`. Each contains one schema-1
  manifest with `version`, GitHub release `url`, `sha256`, and byte `size`.
- Beta feed includes stable releases when they supersede the beta. Semantic
  version comparison prevents downgrades, including beta.9 versus beta.10.
  A stable channel never offers a prerelease. Feed 404 means not published.
- No cookies or authorization headers. Generic `inlaut-Windows-Updater/1`
  user agent, no installed-version query parameter. A check is attempted at most
  every 24 hours while running, with a persisted timestamp and 30-second timeout.
  Failed background attempts stay quiet until the next interval; manual checks
  display errors. HTTP redirects are restricted to the site and GitHub asset hosts.
- Feeds are limited to 16 KiB, packages to 600 MiB, and downloads to 10 minutes.
  Cancelled/failed staging downloads are removed. Bytes and SHA-256 must match.
- WinVerifyTrust validates Windows Authenticode trust, including revocation.
  Certificate verification can contact Windows/CA services. The package must use
  the exact SHA-256 certificate fingerprint of the trusted installed Inlaut.exe,
  and have the expected signed ProductName and ProductVersion. An unsigned local
  build cannot install updates. There is no development bypass in production.
- The separately published, self-contained Inlaut.UpdateHost.exe is copied to a
  unique local staging directory and its signer checked before it is started.
  After the app exits cleanly (no recording/transcription/settings editing), the
  helper checks the package again under a read lock, runs the per-user Inno
  installer into the existing directory, and restarts the installed app. It does
  not need administrator privileges. A setup failure is reported; it does not
  silently mark the update installed. Existing settings/model data are retained.
- Installer AppId and install directory must stay unchanged for beta-to-final
  upgrades. Do not create a parallel stable installation. Automatic rollback is
  not implemented; retain the prior signed installer for recovery. Partial Inno
  installation failure and power loss still require release qualification.

## SignPath release sequence (required before publication)

1. Build/test the exact source. Build-Beta.ps1 produces an unsigned local test
   installer and a payload containing Inlaut.exe and Inlaut.UpdateHost.exe.
2. Sign the payload's Inlaut.exe and Inlaut.UpdateHost.exe through the configured
   SignPath policy with the same project certificate and timestamp. Include other
   first-party binaries in the signing policy as appropriate. Never alter the
   signed binaries afterwards. SignPath account/policy setup remains external.
3. Recompile `inlaut.iss` with that **signed payload**, then sign the resulting
   installer through SignPath with the same certificate. Signing only the outer
   installer is insufficient: the installed app is the updater's trust anchor.
4. Run New-UpdateManifest.ps1 with the signed installer, installed app executable,
   helper, version and release tag. It refuses unsigned/mismatched artifacts.
   Regenerate SHA256SUMS.txt **after signing**, which changes the installer bytes.
5. Publish the signed installer as the exact GitHub release asset in the manifest.
   Re-download it and verify hash/signature. Only then deploy the manifest to the
   corresponding website feed. A final release must update both feeds so beta
   users can graduate. Never point a feed at an unpublished asset.
6. Qualify two successive **signed** builds on a test installation: check → offer
   → download → verify → clean exit → installation → restart, preserving settings.
   Test decline/cancel, network failure, busy dictation, and installer failure.
   This full signed upgrade cannot be certified with the unsigned development
   builds available on the current machine.

Certificate renewal needs planning: exact certificate pinning deliberately rejects
a different certificate, even with the same publisher name. Before rotation, ship
a bridge release signed by the old certificate that explicitly trusts the new
fingerprint in code, then rotate. This bridge is not yet implemented; never change
certificate identity without preparing and testing it. There is no blanket trust
for all SignPath projects or an issuer name supplied by an unsigned feed.

No feed or signed production artifact has been published by this implementation.

References: [SignPath Authenticode](https://docs.signpath.io/artifact-configuration/reference),
[WinVerifyTrust](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/nf-wintrust-winverifytrust).
