# -------------------- setup-trollstore-app.ps1 --------------------
$ErrorActionPreference = 'Stop'

function Ensure-Dir($p) { if (!(Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Text($path, $text, [switch]$Unix) {
  $dir = Split-Path -Parent $path
  if ($dir) { Ensure-Dir $dir }
  if ($Unix) {
    $text = $text -replace "`r`n", "`n"
    Set-Content -Path $path -Value $text -NoNewline -Encoding Ascii
  } else {
    Set-Content -Path $path -Value $text -Encoding UTF8
  }
  Write-Host "Wrote $path"
}

# --- Minimal iOS app (UIKit) that shows a message; good for TrollStore smoke test ---
$appMain = @'
#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary*)opts {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  UIViewController *vc = [UIViewController new];
  vc.view.backgroundColor = [UIColor systemBackgroundColor];
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
  label.text = @"MoonlightServer (stub) installed via TrollStore.\nBuild succeeded.";
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [vc.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
    [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    [label.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:20.0],
    [label.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-20.0]
  ]];
  self.window.rootViewController = vc;
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
'@

$infoPlist = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>MoonlightServer</string>
  <key>CFBundleExecutable</key>
  <string>MoonlightServer</string>
  <key>CFBundleIdentifier</key>
  <string>com.example.trollmoonlight</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MoonlightServer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>MinimumOSVersion</key>
  <string>14.0</string>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UIRequiredDeviceCapabilities</key>
  <array>
    <string>arm64</string>
  </array>
  <key>UIRequiresFullScreen</key>
  <true/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>

  <!-- Local Network privacy for Bonjour (Moonlight discovery later) -->
  <key>NSLocalNetworkUsageDescription</key>
  <string>This app uses the local network for discovery/streaming.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_nvstream._tcp</string>
  </array>
</dict>
</plist>
'@

$entitlements = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Optional: helps Bonjour on some networks. TrollStore preserves entitlements. -->
  <key>com.apple.developer.networking.multicast</key>
  <true/>
</dict>
</plist>
'@

# --- Build script: compiles app with xcrun and packages a .tipa with ldid ---
$buildSh = @'
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
LDFLAGS=( -framework UIKit -framework Foundation )

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
'@

# --- GitHub Actions workflow (macOS runner builds the .tipa) ---
$workflow = @'
name: build-tipa

on:
  workflow_dispatch:
  push:
    branches: [ feature/trollstore-app, main ]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: |
          brew update
          brew install ldid
      - name: Build .tipa
        run: |
          bash scripts/build_tipa.sh
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MoonlightServer-tipa
          path: build/MoonlightServer.tipa
'@

# Write files
Write-Text 'src\moonlight\app\AppMain.mm' $appMain
Write-Text 'src\moonlight\app\Info.plist' $infoPlist
Write-Text 'entitlements.trollstore.plist' $entitlements
Write-Text 'scripts\build_tipa.sh' $buildSh -Unix
Write-Text '.github\workflows\build-tipa.yml' $workflow -Unix

Write-Host "`nAll files written. Next steps:"
Write-Host "  git add ."
Write-Host "  git commit -m 'Add TrollStore iOS app stub + tipa builder'"
Write-Host "  git push origin feature/trollstore-app"
# -------------------- end of script --------------------
