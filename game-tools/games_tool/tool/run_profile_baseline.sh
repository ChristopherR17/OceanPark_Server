#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p build/perf
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="build/perf/frame_profile_${STAMP}.log"

echo "Starting profile run. PERF lines will be written to:"
echo "  $LOG_FILE"
echo ""
echo "Run your manual scenarios, then stop with Ctrl+C."
echo ""

flutter run \
  -d macos \
  --profile \
  --dart-define=PERF_FRAME_LOG=true \
  --dart-define=PERF_FRAME_LOG_INTERVAL_MS=5000 \
  --dart-define=PERF_FRAME_WARMUP_MS=1200 \
  --dart-define=PERF_FRAME_BUDGET_MS=16.67 \
  "$@" 2>&1 | tee "$LOG_FILE"
