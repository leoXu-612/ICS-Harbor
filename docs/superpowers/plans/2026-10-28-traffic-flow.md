# Harbor traffic flow implementation

User authorizes implementation immediately after telemetry validation. Existing local icon/quiet-launch changes must stay intact.

Validation: Origin2026's embedded Python sent 1,572,864 bytes and received 786,432 bytes over a controlled local TCP connection. nettop attributed counters and 127.0.0.1 endpoints to the same macOS PID as Origin; per-second deltas matched the 128 KiB/s upload / 64 KiB/s download test. Validate native executable path ties that PID to the selected runtime. This proves socket metadata and byte attribution, not decrypted content or remote service ownership.

1. Core: parse nettop CSV snapshots, retain per-socket rows only, compute monotonic byte deltas using sample time, baseline first observations and counter resets. Unit tests for quoted CSV, IPv6, process totals vs socket rows, disappearance/reuse, resets, negative/invalid counters.
2. Native service: visible-page polling, bounded subprocess lifetime/output; map only runtime-owned PIDs via proc_pidpath and process start identity, match exact registered Windows paths or explicitly show environment/shared process. Collect process CPU/RSS. No IP/DNS uploads or disk history. Report unavailable/stale distinctly from zero.
3. UI: SwiftUI Canvas directed flow bands, colored upload/download, stable endpoint nodes, traffic-dependent particles. Pause freezes the snapshot; reduced motion removes particles; hidden/inactive page stops collection. Detail selection shows endpoints, byte totals since observation, rates and timestamp. Existing app actions remain above monitor. Empty states explain no app/connection/traffic.
4. Integrate into application detail and unselected overview; test real controlled traffic through installed UI, idle and pause. Check source/build/tests, CPU while visible vs hidden. Install only after owned test runtime exits; preserve app/state backup.

Motion reference: Amicro's public presets (smooth/gentle, Subhan-code/Amicro--Micro-transitions-). Native SwiftUI implementation; no React dependency or copied components.
