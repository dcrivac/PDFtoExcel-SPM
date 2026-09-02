#!/bin/bash
#
# Assemble PDFtoExcel.app from the SwiftPM build.
#
# SwiftPM produces a bare Mach-O executable, not an application bundle, so a
# double-clickable and signable app has to be put together by hand. Info.plist
# is already embedded in the binary by the linker (see Package.swift); this
# script builds the surrounding bundle and applies the entitlements, which can
# only be attached at signing time.
#
#   ./Scripts/make-app.sh                 # debug build, ad-hoc signature
#   ./Scripts/make-app.sh release         # release build, ad-hoc signature
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./Scripts/make-app.sh release
#
set -euo pipefail

CONFIGURATION="${1:-debug}"
IDENTITY="${CODESIGN_IDENTITY:--}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

PLIST="Sources/PDFtoExcel/Info.plist"
ENTITLEMENTS="Sources/PDFtoExcel/PDFtoExcel.entitlements"
APP="build/PDFtoExcel.app"

echo "Building ($CONFIGURATION)..."
swift build -c "${CONFIGURATION}"

BIN="$(swift build -c "${CONFIGURATION}" --show-bin-path)/PDFtoExcel"
[ -x "${BIN}" ] || { echo "error: no executable at $BIN" >&2; exit 1; }

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${PLIST}")"

echo "Assembling $APP..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/$EXECUTABLE_NAME"
cp "${PLIST}" "${APP}/Contents/Info.plist"

if [ "${IDENTITY}" = "-" ]; then
    echo "Signing ad-hoc (set CODESIGN_IDENTITY for a real identity)..."
    # The hardened runtime is deliberately omitted here: it is required for
    # notarization but needs a real Developer ID, and pairing it with an ad-hoc
    # signature produces an app that will not launch.
    codesign --force --sign - --entitlements "${ENTITLEMENTS}" "${APP}"
else
    echo "Signing as $IDENTITY..."
    codesign --force --sign "${IDENTITY}" --entitlements "${ENTITLEMENTS}" \
        --options runtime --timestamp "${APP}"
fi

codesign --verify --strict "${APP}"

echo
echo "Built $APP"
echo "  identifier:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist")"
echo "  entitlements: $(codesign -d --entitlements - "${APP}" 2>&1 | grep -c '\[Key\]' || true) keys"
echo
echo "Run it with:  open $APP"
