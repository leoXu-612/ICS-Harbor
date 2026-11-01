# NieR display preflight — 2026-10-30

Harbor 0.5.2 build 15 adds automatic preflight for Steam app 524220. It follows the current primary display. Other titles, direct Steam launches, and hot-plug while a game is running are outside scope.

The verified incident involved a stale Graphic.ini output name and a secondary-screen cursor clamped at the desktop edge. Correcting SystemData.dat's monitor field alone did not change placement. Preserving and removing the stale Graphic.ini then restored the primary display and bidirectional camera movement, confirmed by the user.

## Behavior

- A bundled read-only C# probe runs in the selected Wine runtime using its existing Mono compiler. DXGI enumerates the active primary output; QueryDisplayConfig/DisplayConfigGetDeviceInfo identifies its physical monitor name. Legacy generic PnP labels and localized macOS labels are deliberately not used.
- Resolve that Windows user's Documents directory through the container's drive mappings. Only the verified 72-byte SystemData.dat format and 129-byte hex Output field are accepted.
- Healthy settings are unchanged. A stale index or name creates verified private backups, changes only the four-byte monitor field, and removes the backed-up Graphic.ini so the game rebuilds it. Save slots, GameData, NAIOM, rendering quality, resolution, and window mode are untouched.
- Process enumeration must succeed. Check for NieRAutomata.exe globally before reading and immediately before mutation, because containers may share Documents. Serialize repair transactions off the UI thread. Recheck source bytes after backup; roll back on write failure.
- Cancellation or a display-change notification prevents admission of new writes. Already-admitted writes finish or roll back; stopping observation cannot undo them. Check display changes again before dispatch, including no-op cases.
- Unsupported data, missing runtime/compiler, ambiguous mirrored outputs, or failed probing stop that launch with a reason. No guessed repair occurs. Preflight results and backup paths appear in the launch activity log.

## Validation

- Final Swift suite: 98 tests, 0 failures, 3 opt-in tests skipped.
- The read-only Wine display integration was separately enabled and passed, alongside the full then-current suite (98 tests, 2 other opt-in tests skipped). It detected output 0 and the real external model; temporary fixtures exercised repair and a second no-op check.
- Fixtures cover valid configuration, stale output, unplug/replug and changed indices, unknown format, backup failure, invalid Documents paths, failed process enumeration, and a game starting during backup. Physical display unplug/replug was not performed.
- Release build and installed app signature verified. The source change preserves the pre-existing traffic/icon/application work in the dirty checkout.
- Installed UI testing exposed Documents privacy authorization blocking an on-main file open. Build 15 performs game-file I/O on a serial background queue; macOS Documents authorization remains an explicit user-controlled requirement. No Full Disk Access is requested.

Steam Cloud may overwrite settings after preflight. A launch-time check cannot guarantee against that window or changes made after the game starts. Installed build 15 acceptance passed after the user authorized Documents access: the UI reported the current primary model, Steam connected, and the NieR game process/window was detected. Hashes of all six pre-existing game configuration/save files remained unchanged for this healthy configuration. Detailed local evidence is in Harbor TestReports/NierDisplayPreflight-20261030; physical unplug/replug remains fixture-tested only.
