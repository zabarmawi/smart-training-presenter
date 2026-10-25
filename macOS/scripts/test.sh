#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/test-cache
swiftc -swift-version 5 -D TESTING -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Sources/RecoveryWriter.swift Sources/Store.swift Sources/SharePreferences.swift Sources/SharingSession.swift Sources/SharedSlideCanvas.swift Sources/PageRasterService.swift Sources/UIAppearance.swift Sources/TimeSourcePolicy.swift Sources/PresenterWindowState.swift Sources/Store+Conversion.swift Sources/Store+Files.swift Sources/TrainingLibrary.swift Sources/GuideReader.swift Sources/LibraryPreparation.swift Sources/Store+Library.swift Tests/Tests.swift Tests/EnhancedTests.swift -o build/PresenterTests
PRESENTER_DISABLE_OCR=1 PRESENTER_CACHE="$PWD/build/test-cache" build/PresenterTests "$PWD/build" "$PWD/../test-materials" | tee build/test.log
