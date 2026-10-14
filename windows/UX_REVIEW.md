# Windows settings and tray review — 2026-10-14

Expert inspection using [Jakob Nielsen's usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/),
not a user study. Evidence: Windows settings/menu code, native-control bitmap
renders at this machine's 200% scaling, and Sources/SettingsView.swift comparison.
Native-control renders do not establish real taskbar placement or behavior on
every monitor. macOS was inspected in source, not run on this machine.

## Tray menu: addressed in beta.4

The icon font was drawn at an em size equal to the entire bitmap. Visible
outlines could extend beyond the canvas and be clipped. Fit actual vector glyph
bounds inside a transparent inset instead. Retain consistent icon/text columns
and 40 logical-pixel minimum rows, with font-dependent extra room.

Menu preparation also ran before the application updated its status, recording
icon and shortcut. Layout now runs after Opening subscribers update those values.
Nine glyphs tested for visible ink and transparent outer borders at seven sizes
covering 100–300%; main/submenu renders visually inspected at 200%. Existing
settings resize and HUD/recovery checks passed. Real mixed-DPI monitor placement
and high-contrast selected icons still require visual acceptance testing.

## Settings findings and priorities

Severity: P1 = important for beta usability; P2 = subsequent capability or polish.
These recommendations are NOT implemented by the menu fix.

| Priority / heuristic | Finding | Proposed change / acceptance |
| --- | --- | --- |
| P1 — recognition rather than recall | Clipboard insertion lives under Help & Diagnostics, although multiline Office depends on it. | Put input method in Settings > Text input. Explain direct vs clipboard and Excel F2 cell editing. Keep the existing default; synchronize any tray shortcut. |
| P1 — user control and consistency | Voice commands and German ß correction exist in Windows TextPipeline but have no persisted user controls. macOS offers both. | Add independent switches with examples; persist settings, apply to the pipeline, test restart and disabled behavior. |
| P1 — visibility of status | No microphone or recognizer status in settings; Model folder is a prominent bottom action without explaining the active model. | Show active microphone, German offline model, readiness and disk size. Move folder access into a secondary details section. |
| P1 — user control / recovery | No microphone selector or test meter. | Add system-default/device selection and explicit start/stop test with a meter and clear recording state. Handle unplug/replug and unavailable devices before claiming support. |
| P1 — error prevention | Key capture accepts broad key choices; recommended choices and conflict consequences are unclear. Save failures are swallowed, yet UI reports Saved. | Prefer a compact current-key row with recommended F-key choice, warn about typing/OS conflicts, reject unsupported bindings. Surface save errors; never claim persistence on failure. |
| P2 — minimalist design | Most of the window is devoted to oversized key/preset buttons; a scrollbar is present even with few controls. Pause information is at the bottom. | Compact key controls, grouped sections, pause notice near the top, persistent Done action and keyboard navigation. Verify text scaling and small windows without truncation. |
| P2 — help and recovery | Settings do not explain where a failed/partial dictation can be recovered, or the limits of the beta. | Link Last dictation and concise local help; show version and feedback access. Distinguish metadata diagnostics from opt-in saved audio/text. |

## macOS parity: do not expose nonfunctional choices

| Capability present in Mac settings | Windows state / next step |
| --- | --- |
| Recognition language and engine/model | Current bundled Windows model is German. Show that fact; add choices only after compatible engines/models and measured quality are available. |
| Trigger mode / shortcut | Hold and double-tap behavior exist; configurable mode and combinations need implementation/testing. |
| Microphone, indicator position, sounds, launch at login | Missing settings. Implement device selection first, then optional behavior controls with persistence and lifecycle tests. |
| Voice commands, ß | Pipeline exists; ready for settings wiring and regression tests. |
| Tidy dictations and self-corrections | Not equivalent to the Mac implementation. Separate backlog work; do not promise Apple Intelligence behavior on Windows. |
| Replacements | Pipeline supports a rules list, but Windows lacks editor and persistence wiring. Add whole-word examples, validation and reversible edits. |
| Snippets, import/export | Need implementation and shared format design. Preserve literal snippet contents; coordinate with issue #20. |
| Updates | No equivalent trusted Windows update path yet. Define signing/update policy before offering automatic update controls. |
| Permissions | Use Windows-specific microphone/input help, not a copy of macOS Accessibility controls. Never imply admin privileges are routinely required. |

Suggested sections: **Dictation** (key/mode/microphone), **Recognition** (model and
supported language), **Text input** (method, voice commands, ß, later replacements),
**Behavior** (indicator/sounds/startup), **Help & privacy** (recovery, diagnostics,
version). Initially omit empty sections rather than filling them with disabled
future features. Preserve per-app considerations from #17 and boundary work #20.

For each added setting, verify immediate effect, restart persistence, accessible
label/focus order, small-window/DPI layout, and safe behavior during recording.
Keep synthetic tests separate from private recordings and user settings.

## Beta.5 implementation update

The settings recommendations above were implemented in beta.5, including grouped
controls, device selection/test, persisted text options/rules, literal snippets
and Mac-schema import/export, top/bottom indicator, sounds and per-user startup.
See HANDOFF.md for exact test evidence and limits, and CRASH_REPORTS.md for the
new explicitly opt-in reporting flow. Original audit tables describe the beta.4
baseline; language/model choices, tidying/self-corrections, trusted automatic
updates and cross-dictation boundaries remain separate work.
