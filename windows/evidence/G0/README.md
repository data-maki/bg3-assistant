# G0 platform evidence

No G0 result is considered passed until dated evidence names the exact commit, Windows
build, controlled host executable/window, display and DPI configuration, harness build,
observed result, and artifact paths.

Current state: **partial controlled-host evidence; G0 remains pending**.

The `spikes/OverlayHarness` application is the first proof surface. The exact-name x64
controlled host now passes on one 200%-scaled display for both borderless-style and
windowed-style geometry. Physical 100/150% scaling, two monitors, and native x64 hardware
remain outstanding.

The repository now also produces an unsigned, self-contained x64 development MSIX with
Microsoft MakeAppx. This proves manifest and package construction only. The current development
machine is Windows 11 Pro build 26200 on ARM64, so it is not a substitute for the required
native x64 clean-VM, update, signing, Defender, or controlled-host matrix.

Live BG3 installation, renderer, gameplay, and input testing are explicitly outside the
Windows MVP scope. Screenshot capture and microphone/speech are approved exclusions. See
[`../mvp-scope-2026-07-25.md`](../mvp-scope-2026-07-25.md).

See [`development-package-2026-07-25.md`](development-package-2026-07-25.md).
See also [`automated-overlay-hwnd-2026-07-25.md`](automated-overlay-hwnd-2026-07-25.md).
Controlled-host evidence is in
[`controlled-window-matrix-2026-07-25.md`](controlled-window-matrix-2026-07-25.md).
Historical capture research, now excluded from the MVP, is in
[`capture-permission-2026-07-25.md`](capture-permission-2026-07-25.md).
Packaged startup evidence is in
[`packaged-permissions-2026-07-25.md`](packaged-permissions-2026-07-25.md).
