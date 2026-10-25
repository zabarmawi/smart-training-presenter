#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ocr-integration-cache build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/TimeSourcePolicy.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Tests/OCRIntegration.swift -o build/OCRIntegration
PRESENTER_CACHE="$PWD/build/ocr-integration-cache" build/OCRIntegration "$PWD/Fixtures/third-bag" "$PWD/build/ocr-results.json"
