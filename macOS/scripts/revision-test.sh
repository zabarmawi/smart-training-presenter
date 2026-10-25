#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/TimeSourcePolicy.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Tests/RevisionIntegration.swift -o build/RevisionIntegration
PRESENTER_CACHE="$PWD/build/revision-cache" build/RevisionIntegration "$PWD/build"
