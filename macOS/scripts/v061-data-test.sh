#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/v061/data build/module-cache
SOURCES=(Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/TimeSourcePolicy.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Sources/TrainingLibrary.swift)
swiftc -swift-version 5 -module-cache-path build/module-cache "${SOURCES[@]}" Sources/GuideReader.swift Sources/SharePreferences.swift Tests/TimePolicyTests.swift -o build/v061/TimePolicyTests
build/v061/TimePolicyTests "$PWD/build/v061/data/time-policy.txt"
swiftc -swift-version 5 -module-cache-path build/module-cache "${SOURCES[@]}" Tests/PrivacyDataTests.swift -o build/v061/PrivacyDataTests
build/v061/PrivacyDataTests "$PWD/build/v061/before/User/Library" "$PWD/build/v061/data"
swiftc -swift-version 5 -module-cache-path build/module-cache "${SOURCES[@]}" Sources/GuideReader.swift Sources/LibraryPreparation.swift Tests/V061ReaderTests.swift -o build/v061/ReaderTests
build/v061/ReaderTests "$PWD/build/v061/before/User/Library" "$PWD/build/v061/data/reader.json"
