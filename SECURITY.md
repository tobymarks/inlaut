# Security

## Supported versions

Only the latest release of inlaut receives fixes. The app checks for updates once a day (unless you turned that off) and updates are signed.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

- Preferred: use [GitHub's private vulnerability reporting](https://github.com/tobymarks/inlaut/security/advisories/new) ("Security" → "Report a vulnerability").
- Or write to hallo@inlaut.de. Mail is not encrypted end to end, so share details only as far as you are comfortable and ask for another channel if you need one.

Say which version you used, what you did and what happened. Never include dictated text or recordings.

inlaut is maintained by one person in their spare time. You will get a first answer within 14 days, usually much sooner. Fixes ship as a regular signed update, and the release notes name the problem once a fixed version is available. There is no bug bounty.

## Scope

- The app in this repository, including the model download and the update mechanism.
- The website and update feed on inlaut.de (`site/`).

Problems in dependencies (FluidAudio, Sparkle, the speech model) are best reported to those projects; tell us too if inlaut is affected.

## How inlaut is built to limit damage

- Speech is recognised on the Mac. There is no server that receives audio or text, no account and no telemetry.
- The speech model is downloaded from a pinned revision, and every file is checked against a SHA-256 hash before it is used.
- Releases are signed with a Developer ID, notarized by Apple and use the Hardened Runtime. Sparkle only installs updates whose signature matches the key built into the app.
- Logs contain lengths and timings, never dictated text.
