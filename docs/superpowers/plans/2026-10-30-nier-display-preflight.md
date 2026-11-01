# NieR display preflight

Scope: Steam 524220 launched from Harbor. Follow the current Windows primary output as enumerated by the selected Wine runtime's DXGI; do not infer monitor indices from macOS enumeration. The proven failure involved an obsolete Graphic.ini output name overriding SystemData.dat's monitor index.

Approach: ship a read-only C# display probe, compiled using the runtime's existing Wine Mono compiler. It reports the active primary DXGI output index, Windows monitor description and Documents path. Use QueryDisplayConfig / DisplayConfigGetDeviceInfo to obtain the physical model name that NieR persists (the legacy PnP description and localized macOS built-in label are unsuitable). Reject display attachment/primary changes during probing. Swift validates the known 72-byte NieR settings format and existing output hex format. When either target index or output name is stale, preserve verified copies before changing only the monitor field and removing the stale Graphic.ini. No changes to saves, NAIOM, graphics quality or display mode. Valid configuration is a no-op. Other games bypass the feature.

Alternatives rejected: fixed monitor 0 (not an enumeration guarantee), resetting every launch (unnecessary writes and settings churn), host-only monitor mapping (not the renderer's enumeration), runtime hot-plug intervention (could interrupt a running game).

Implementation:
1. Add failing policy/fixture tests for valid configuration, stale generic output, unplug/replug, reordered outputs, malformed data, backups, repeat no-op and cancellation/running protection.
2. Add Core repair and probe request/report types; add read-only probe resource and async launch service with bounded completion, actionable failure and no UI automation.
3. Integrate after checking for an already-running game and before dispatch; retain a visible activity log. Do not repair shared settings while any NieRAutomata.exe is running.
4. Run full Swift tests, real Wine read-only probe and temporary-fixture repair tests, release build and independent review. Preserve all pre-existing source changes.
5. Install locally only once Wine runtimes are no longer active, respecting the existing build/install TCC attribution safeguard. Do not terminate games for an update.

Limits: Steam/direct EXE launches bypass Harbor. In-game hot-plug is outside scope. Steam Cloud can change configuration after the preflight; no claim to intercept that window. Unknown formats or inability to identify an unambiguous primary display must not result in guessed writes.
