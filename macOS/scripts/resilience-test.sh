#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/Smart Training Presenter.app}"
FOLDER="${PRESENTER_RESILIENCE_OUTPUT:-$PWD/build/resilience-check}"
mkdir -p "$FOLDER/cache"
rm -f "$FOLDER/seed-ready.txt" "$FOLDER/resilience-results.txt"
PRESENTER_CACHE="$FOLDER/cache" "$APP/Contents/MacOS/SmartTrainingPresenter" --resilience-seed "$FOLDER" > "$FOLDER/seed.log" 2>&1 &
CHILD=$!
trap 'kill -TERM "$CHILD" 2>/dev/null || true' EXIT
for ((i=0;i<40;i++)); do
    [[ -f "$FOLDER/seed-ready.txt" ]] && break
    sleep 1
done
[[ -f "$FOLDER/seed-ready.txt" ]] || { echo 'FAIL: seed did not launch'; exit 1; }
kill -KILL "$CHILD"
wait "$CHILD" 2>/dev/null || true
PRESENTER_CACHE="$FOLDER/cache" "$APP/Contents/MacOS/SmartTrainingPresenter" --resilience-check "$FOLDER" > "$FOLDER/verify.log" 2>&1 &
CHILD=$!
for ((i=0;i<40;i++)); do
    [[ -f "$FOLDER/resilience-results.txt" ]] && break
    sleep 1
done
[[ -f "$FOLDER/resilience-results.txt" ]] || { echo 'FAIL: verify did not launch'; exit 1; }
cat "$FOLDER/resilience-results.txt"
! grep -q '^FAIL:' "$FOLDER/resilience-results.txt"
wait "$CHILD"
