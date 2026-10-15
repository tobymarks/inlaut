# Windows release signing

Status (2026-10-15): prepared, not activated. The existing SignPath organization
`f511eba1-0577-4bb3-927b-da77f62e623d` is a free trial with no certificates. Project `inlaut` exists
with the repository URL recorded and only the default PE artifact configuration;
this is not yet a GitHub Trusted Build System connection. The trial rejected the
parameterized artifact configurations because that feature is unavailable. Foundation acceptance, a production certificate, GitHub integration,
CI credentials and a successful signed upgrade are still pending. Do not publish
an unsigned build as a signed release or install a test root on users' devices.

## Foundation onboarding

Use https://signpath.org/apply.html. The maintainer selected the free Open Source
program. Acceptance is decided by the Foundation, not implied by a trial account.
The project is young and Windows currently has CI artifacts rather than a public
release; disclose that and ask whether an unsigned, explicitly labelled preview
release is needed for evaluation. Do not invent adoption or claim sponsorship
before acceptance. Review https://signpath.org/terms.html, including manual signing
approval, MFA, project reputation, published downloads, and the required public
code signing policy/attribution. Keep marketing consent optional and off.

After acceptance, use the Foundation-provisioned organization/project/certificate;
the trial organization ID may not be the final one. A local application draft is
kept in the worktree's gitignored `build/signing-tools/foundation-application.txt`.
The Foundation application was submitted on 2026-10-15 with maintainer approval
of the required terms and data processing; marketing consent was left off.
The form confirmed: "Form submitted — Thank you, we'll be in touch soon."
Acceptance and certificate provisioning are still pending.

The downloaded CI installer has ASCII-space-padded PE product/version strings
from Inno Setup; local verification trims only those trailing spaces. Confirm
that SignPath accepts the exact metadata restrictions with a real signing request
after onboarding; this has not been exercised in the trial account.

## SignPath configuration

1. Create/link project `inlaut` to `https://github.com/tobymarks/inlaut` using the
   GitHub.com Trusted Build System. Install the SignPath GitHub App for this
   repository only. Restrict signing to the exact repository and maintained
   branches `main` / `feature/windows-prototype`, and GitHub-hosted builds.
2. Add artifact configurations `windows-payload` and `windows-installer` using
   the XML files here. Both require a `version` parameter and enforce product
   name `inlaut` and that exact product version. Only first-party files listed
   explicitly are signed; bundled .NET/NAudio/Sherpa binaries are not re-signed.
3. Create policy `release-signing` with the approved production certificate and
   timestamping. Require maintainer approval of signing requests. Tobias Marks
   is the maintainer/reviewer/approver; the CI identity only submits requests.
   Do not use a self-signed test certificate for this policy.
4. Restrict the CI identity to this project's signing policy. Put its API token
   directly into the GitHub environment secret `SIGNPATH_API_TOKEN`; never commit
   it or include it in logs, screenshots, shell history, or application drafts.

## GitHub configuration

The GitHub environment `windows-signing` was created on 2026-10-15. It allows
only `main` and `feature/windows-prototype` and requires approval by `tobymarks`
(self-approval is allowed because this is a single-maintainer project). No API
token or certificate variables have been set yet. After Foundation provisioning,
set environment variables:

- `SIGNPATH_ORGANIZATION_ID`: actual Foundation organization ID.
- `SIGNPATH_PROJECT_SLUG`: actual configured project slug (planned: `inlaut`).
- `SIGNPATH_CERTIFICATE_SHA256`: 64 hexadecimal digits of the approved production
  signing certificate (SHA-256 of certificate DER, not a file hash or SHA-1
  thumbprint). Confirm against the certificate in SignPath.

The separate `Windows signed release candidate` workflow is manually dispatched
on a maintained branch. It tests/builds the exact checked-out commit, uploads the
five first-party binaries as a GitHub artifact, requests signing, verifies their
trust/timestamp/fingerprint/product/version, packages those exact signed files,
then submits and verifies the installer. Checksums and the update manifest are
created only after signing. Actions are pinned to commits. No signing secrets are
used by normal PR builds. No public release or website is changed automatically.

The normal Windows Build still creates an unsigned installer for testing. The
signed workflow cannot pass its configuration gate until onboarding is complete.
Do not lower the signature checks to get a green workflow with a trial certificate.

## Qualification and publication

The output artifact `windows-signed-release-candidate` contains the installer,
SHA256SUMS.txt, BUILD.txt and a candidate `windows-beta.json`. The planned release
tag is `windows-v<version>`; it must reference the same source commit as BUILD.txt.
This workflow does not create that tag or publish the manifest. Never deploy the
manifest before the corresponding signed GitHub asset exists and is re-downloaded
and verified. For a stable version, publish the validated manifest to both channels.

Test clean installation and two successive signed versions through the actual
updater on Windows, including clean exit/restart, preferences, cancellation,
busy dictation, and installer failure. Preserve the previous signed installer.
Certificate rotation requires the bridge-release procedure in ../UPDATES.md.
Windows 11/device/standby and compatibility limits remain documented in HANDOFF.md.

References:
- https://docs.signpath.io/trusted-build-systems/github
- https://docs.signpath.io/artifact-configuration/syntax
- https://docs.signpath.io/artifact-configuration/reference
