# Windows UI

The Windows app uses a shared Windows 11 / Fluent-inspired WinForms theme.
This is not a WinUI 3 migration: existing WinForms keyboard behavior, accessibility
objects, window chrome, layout and portable deployment remain in place.

## Reference

- [Windows design guidelines](https://learn.microsoft.com/windows/apps/design/guidelines-overview)
- [Typography](https://learn.microsoft.com/windows/apps/design/signature-experiences/typography)
- [Geometry](https://learn.microsoft.com/windows/apps/design/signature-experiences/geometry)
- [Windows icons](https://learn.microsoft.com/windows/apps/design/iconography/segoe-ui-symbol-font)
- [Reduced animation](https://learn.microsoft.com/windows/win32/winauto/client-area-animation)

## Shared rules

- Segoe UI Variable Text, with Segoe UI fallback; 10.5 pt body, 20 pt page heading.
- Segoe Fluent Icons, with Segoe MDL2 Assets fallback. Never use emoji as command icons.
- Neutral app background and raised content surfaces; one blue accent for primary actions.
- Follow Windows app light/dark preference. High contrast uses system colors.
- Controls use 4 logical-pixel corners; transient surfaces use 8. Request system-rounded
  window chrome through DWM on Windows 11. Windows 10 keeps its native window chrome.
- Native title bars and task dialogs. No simulated Mica or wallpaper blur.
- DPI-aware drawing, visible keyboard focus and inherited button/menu accessibility.
- The settings layout remains one-way and resizable: no child SizeChanged handler may
  write sizes back to a parent. Keep the existing 560 × 560 logical-pixel client size.
- Short menu labels. Selected trigger shown in the shortcut column. Diagnostic commands
  are grouped in a submenu, not mixed with everyday actions.
- Recording HUD never takes focus; animations respect the Windows client-area setting.

## Validation

The cross-platform build validates the C# and Windows API declarations. UI smoke tests
exercise repeated resizing on Windows. Native light/dark/high-contrast rendering,
125–200% scaling, keyboard navigation and tray placement require a Windows desktop.
The browser preview is a design illustration, not evidence of native rendering.
