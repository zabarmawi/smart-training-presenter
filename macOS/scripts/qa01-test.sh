#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/qa01-fix/tests build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/TimeSourcePolicy.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Sources/TrainingLibrary.swift Tests/QA01Tests.swift -o build/qa01-fix/QA01Tests
PRESENTER_CACHE="$PWD/build/qa01-fix/tests/cache" build/qa01-fix/QA01Tests "$PWD/build/qa01-fix/before/Library" "$PWD/build/qa01-fix/tests" > build/qa01-fix/tests.log 2>&1
tail -1 build/qa01-fix/tests.log
