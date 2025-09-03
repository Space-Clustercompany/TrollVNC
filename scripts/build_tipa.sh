#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MoonlightServer"
BUNDLE_ID="${BUNDLE_ID:-com.example.trollmoonlight}"
VERSION="${VERSION:-0.1.0}"
OUT_DIR="build"
APP_DIR="$OUT_DIR/Payload/$APP_NAME.app"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CXX=$(xcrun --sdk iphoneos -f clang++)  # C++ linker
ROOT="$(pwd)"

echo "==> Using SDK: $SDK"
echo "==> Output: $OUT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR"

# --- Sources (UI app + Moonlight transport; see step 2) ---
SRCS=(
  src/moonlight/gs_mdns.mm
  src/moonlight/gs_video_vt.mm
  src/moonlight/gs_rtp_video.cpp
  src/moonlight/gs_rtsp.mm
  src/moonlight/test_pattern.mm
  src/moonlight/app/AppMain.mm
)

# NOTE the min iOS version flag fixes some ldid crashes
CXXFLAGS=( -isysroot "$SDK" -arch arm64 -fobjc-arc -std=c++17 -ObjC++ -I./src -miphoneos-version-min=14.0 )

LDFLAGS=(
  -framework UIKit
  -framework Foundation
  -framework CoreGraphics
  -framework CoreMedia
  -framework CoreVideo
  -framework VideoToolbox
  -framework AVFoundation
)

echo "==> Compiling $APP_NAME"
"$CXX" "${CXXFLAGS[@]}" "${SRCS[@]}" "${LDFLAGS[@]}" -o "$APP_DIR/$APP_NAME"

echo "==> Preparing Info.plist"
cp src/moonlight/app/Info.plist "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Info.plist"

echo "==> Fakesigning (ldid, with codesign fallback)"
set +e
if command -v ldid >/dev/null 2>&1; then
  ldid -S "$ROOT/entitlements.trollstore.plist" "$APP_DIR/$APP_NAME"
  STAT=$?
else
  STAT=1
fi
set -e

if [ $STAT -ne 0 ]; then
  echo "ldid failed or missing; falling back to ad-hoc codesign"
  codesign -s - --force --entitlements "$ROOT/entitlements.trollstore.plist" "$APP_DIR/$APP_NAME"
fi

echo "==> Packaging IPA and TIPA"
pushd "$OUT_DIR" >/dev/null
zip -qry "$APP_NAME.ipa" Payload
cp "$APP_NAME.ipa" "$APP_NAME.tipa"
popd >/dev/null

echo "==> Done."
echo "TIPA: $(pwd)/$OUT_DIR/$APP_NAME.tipa"
