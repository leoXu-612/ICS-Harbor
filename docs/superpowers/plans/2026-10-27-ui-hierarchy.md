# Harbor UI Hierarchy Implementation Plan

**Goal:** Improve task guidance and visual hierarchy, install the native update without changing existing container indices.
**Architecture:** Keep AppModel services and persistence intact. Add pure guidance decisions to HarborCore, regroup SwiftUI navigation, and reuse existing actions. No new runtime or data migration.
**Tech Stack:** SwiftUI, AppKit, SwiftPM.
**Spec:** `DESIGN.md` and the user's direct implementation request.

## Constraints

Preserve existing container IDs, wrapper paths, application entries, presets, favorites and bindings. Do not modify shared Steam-library registration or launch games during visual QA. Work locally on the UI branch; no remote publication. Canonical changing work state is the `ICS-Harbor-UI-20261027` claude-mem list.

## Implementation

1. `GuidanceTests.swift` first: prove linked-only environments cannot be installation targets, ready idle targets outrank busy ones, unknown readiness cannot invent readiness, and pending/global tasks prevent new work. Add `ApplicationGuidance` only after observing failure. Preserve index fields in existing state round-trip tests.
2. Update `ContentView`, `LibraryView`, `ApplicationsView`, `ContainersView`, `SteamSessionControls`, `GameInspector`, and shared components. Add `GuideView` and focused guidance components. Maintain original AppModel action methods. Visual tests compare the current weak guidance against concrete rendered task flows.
3. Bump to 0.5.0, run the full test suite and native layout checks, review the diff, install while Wine is stopped, compare protected state fields, and remove validated old app bundles and generated outputs. Keep source and the small index backup.

## Review focus

- Linked-only or partially initialized environments must not offer an invalid installation as the primary next step.
- Narrow windows and long titles must retain complete actionable controls.
- Shared-library conflicts must remain blocked and become visible, never be silently repaired.
- Dark mode must retain readable secondary text and meaningful keyboard focus.
- Any replacement/cleanup must exclude actual Wine containers and all user data.

## Checks

`swift test --filter GuidanceTests`: red then green. `swift test`: no regressions; real Wine smoke test remains opt-in. `script/build_and_run.sh --build-only`: compiled and signed app. Native CUA checks: routes, disclosure states, cancel paths, theme and window size. Final data comparison excludes only activity timestamps and compares all protected index fields exactly.
