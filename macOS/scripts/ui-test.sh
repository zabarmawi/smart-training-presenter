#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/Smart Training Presenter.app}"
mkdir -p build/ui-check
rm -f build/ui-check/started.txt build/ui-check/ui-results.txt build/ui-check/Recovery.stpresenter
PRESENTER_CACHE="$PWD/build/ui-check/cache" "$APP/Contents/MacOS/SmartTrainingPresenter" --ui-smoke "$PWD/build/ui-check" "$PWD/Fixtures/تجربة العرض.stpresenter" > build/ui-check/launch.log 2>&1
cat build/ui-check/ui-results.txt
if rg -q '^FAIL:' build/ui-check/ui-results.txt; then exit 1; fi
