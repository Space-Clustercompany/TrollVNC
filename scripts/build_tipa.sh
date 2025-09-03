#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MoonlightServer"
BUNDLE_ID="${BUNDLE_ID:-com.example.trollmoonlight}"
VERSION="${VERSION:-0.1.0}"
OUT_DIR="build"
APP_DIR="$OUT_DIR/Payload/$APP_NAME.app"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CXX=$(xcrun --sdk iphoneos -f clang++)  # use C++ linker

echo "==> Using SDK: $SDK"
echo "==> Output: $OUT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR"

SRCS=(
  src/moonlight/app/AppMain.mm
)

CXXFLAGS=( -isysroot "$SDK" -arch arm64 -fobjc-arc -std=c++17 -ObjC++ -I./src )
# ✅ Add CoreGraphics here to satisfy CGRectZero
LDFLAGS=( -framework UIKit -framework Foundation -framework CoreGraphics )

echo "==> Compiling $APP_NAME"
"$CXX" "${CXXFLAGS[@]}" "${SRCS[@]}" "${LDFLAGS[@]}" -o "$APP_DIR/$APP_NAME"

echo "==> Preparing Info.plist"
cp src/moonlight/app/Info.plist "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Info.plist"

echo "==> Fakesigning with ldid (TrollStore preserves entitlements)"
if ! command -v ldid >/dev/null 2>&1; then
  echo "ldid not found. Install via 'brew install ldid'." >&2
  exit 1
fi
ldid -S entitlements.trollstore.plist "$APP_DIR/$APP_NAME"

echo "==> Packaging IPA and TIPA"
pushd "$OUT_DIR" >/dev/null
zip -qry "$APP_NAME.ipa" Payload
cp "$APP_NAME.ipa" "$APP_NAME.tipa"
popd >/dev/null

echo "==> Done."
echo "TIPA: $(pwd)/$OUT_DIR/$APP_NAME.tipa"
