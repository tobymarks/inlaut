# Local crash reports (Windows beta.5)

inlaut does not automatically transmit crash reports. It keeps a small local
session marker and the last known processing phase. Normal application exit
removes the marker. If it remains at the next start, the app offers a report for
unexpected termination; forced exit, power failure or interrupted shutdown can
also cause this condition, so the UI does not assert that every case was a crash.

Managed unhandled exceptions add exception type, numeric error code and up to
20 reflection-derived method names. No exception message, source path, memory
dump, environment variables, device name, settings, text rules, audio or dictated
text is copied. Native crashes may leave only the marker/phase, without a stack.
Diagnostic write failures do not prevent startup. Files are bounded to the current
session, fault and latest pending report in %LOCALAPPDATA%/inlaut/crash-reports.

On next startup, users can review the entire report, save it locally, defer it,
or discard it. The tray Help & Diagnostics menu can reopen a pending report.
The GitHub action explicitly asks before passing the report to a browser URL:
opening a prefilled URL already transmits that content to GitHub. Final public
issue submission happens in the browser and requires the user's action/account.
Reports too large for a safe URL are instead attached manually as exported JSON.
No API token, background uploader, email sender or telemetry service is present.
A private support-upload endpoint is not part of this beta.

Tests run isolated child processes with clean exit, forced termination and a
recorded simulated fault. They check next-start behavior, deferred/discarded
reports, unknown-stage rejection, redaction of a deliberately private exception
message/path, corrupt/unwritable state and URL-size fallback. The preview dialog
is rendered. No test presses the transfer button or creates a support issue.
Live account submission, native crash stack capture, power-loss and OS-session
shutdown scenarios are not claimed as end-to-end tested.
