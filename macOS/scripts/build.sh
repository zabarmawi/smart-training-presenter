#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="${PRESENTER_DIST:-$PWD/dist}"
ARCH="${PRESENTER_ARCH:-arm64}"
case "$ARCH" in arm64|x86_64) ;; *) echo 'Unsupported architecture'; exit 2;; esac
mkdir -p build/module-cache "$DIST"
APP="$DIST/Smart Training Presenter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" != "--package-only" ]]; then
swiftc -swift-version 5 "${PRESENTER_SWIFT_OPTIMIZATION:--O}" -whole-module-optimization -target "${ARCH}-apple-macosx13.0" -module-cache-path build/module-cache Sources/Core.swift Sources/Countdown.swift Sources/ActivityExtraction.swift Sources/DelimitedTiming.swift Sources/DocumentText.swift Sources/DocumentRevision.swift Sources/PortableProject.swift Sources/ReferenceCatalog.swift Sources/Documents.swift Sources/PowerPointConversion.swift Sources/ImageDeck.swift Sources/RecoveryWriter.swift Sources/Store.swift Sources/SharePreferences.swift Sources/SharingSession.swift Sources/UIAppearance.swift Sources/TimeSourcePolicy.swift Sources/Store+Conversion.swift Sources/Store+Files.swift Sources/TrainingLibrary.swift Sources/GuideReader.swift Sources/LibraryPreparation.swift Sources/Store+Library.swift Sources/LibraryView.swift Sources/SharedSlideCanvas.swift Sources/PageRasterService.swift Sources/SharedPresentationView.swift Sources/Main.swift Sources/ActivityReview.swift Sources/Smoke.swift Sources/QA01Smoke.swift Sources/PowerPointSmoke.swift Sources/AcceptanceSmoke.swift Sources/V061Smoke.swift Sources/TrainerHoverHelp.swift Sources/TrainerDocumentArea.swift Sources/SharingControlPanel.swift Sources/TimeConflictReview.swift Sources/FieldAcceptanceSmoke.swift Sources/PresenterWindowState.swift Sources/AboutApplication.swift Sources/PresentationKeys.swift -o "$APP/Contents/MacOS/SmartTrainingPresenter"
cp Resources/* "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
file "$APP/Contents/MacOS/SmartTrainingPresenter"
fi
if [[ "${1:-}" == "--dmg" || "${1:-}" == "--package-only" ]]; then
    STAGE="$(mktemp -d /tmp/presenter-dmg.XXXXXX)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp README.md "$STAGE/اقرأني.md"
    hdiutil create -volname "Smart Training Presenter ${ARCH}" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Smart-Training-Presenter-${ARCH}.dmg"
    hdiutil verify "$DIST/Smart-Training-Presenter-${ARCH}.dmg"
fi
