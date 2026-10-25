#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/Smart Training Presenter.app}"
mkdir -p build/library-ui/cache
rm -rf build/library-ui/Library
cp -R build/library-check/Library build/library-ui/Library
rm -f build/library-ui/library-ui-results.txt build/library-ui/Recovery.stpresenter
PRESENTER_CACHE="$PWD/build/library-ui/cache" "$APP/Contents/MacOS/SmartTrainingPresenter" --library-smoke "$PWD/build/library-ui" > build/library-ui/launch.log 2>&1
cat build/library-ui/library-ui-results.txt
! rg -q '^FAIL:' build/library-ui/library-ui-results.txt
