#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/library-check/cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/TimeSourcePolicy.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Sources/TrainingLibrary.swift Sources/GuideReader.swift Sources/LibraryPreparation.swift Tests/LibraryIntegration.swift -o build/LibraryIntegration
PRESENTER_CACHE="$PWD/build/library-check/cache" build/LibraryIntegration "$PWD/../test-materials" "$PWD/build/library-check" | tee build/library-check/test.log
