# Performance Baseline Runbook

Use this to capture repeatable scroll/form performance numbers for `games_tool`.

## 1) Run in profile with frame probe

```bash
cd games_tool
./tool/run_profile_baseline.sh
```

Optional: change frame budget (example for 120Hz screens):

```bash
./tool/run_profile_baseline.sh --dart-define=PERF_FRAME_BUDGET_MS=8.33
```

## 2) Execute the 3 manual scenarios

Run each scenario for ~20 seconds on the same screen:

1. Fast wheel/trackpad scroll in a heavy form section (for example `Paths` or `Zones`).
2. Drag the scrollbar thumb end-to-end repeatedly.
3. Keep the form scrolled to mid-list and type quickly in text fields.

Stop with `Ctrl+C`.

## 3) Collect metrics

The profile run writes logs to `build/perf/frame_profile_<timestamp>.log`.

Show only summary lines:

```bash
rg "^\[PERF\]" build/perf/frame_profile_*.log
```

## 4) Record results

Copy one representative line per scenario into this table:

| Date | Commit | Scenario | avg_total_ms | p95_total_ms | p99_total_ms | jank_% |
|---|---|---|---:|---:|---:|---:|
| 2026-03-07 | `<hash>` | Fast scroll |  |  |  |  |
| 2026-03-07 | `<hash>` | Scrollbar drag |  |  |  |  |
| 2026-03-07 | `<hash>` | Typing while scrolled |  |  |  |  |

## Notes

- `[PERF]` lines are produced only when `PERF_FRAME_LOG=true`.
- Warmup frames are ignored by default (`1200ms`).
- Keep input dataset/project constant between runs.
