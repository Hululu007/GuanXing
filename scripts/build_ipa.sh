#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-GuanXing}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.guanxing.player}"
ARCHIVE_PATH="$ROOT/build/GuanXing.xcarchive"
EXPORT_PATH="$ROOT/build/export"
METHOD="${EXPORT_METHOD:-development}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：没有找到 xcodebuild。请在 macOS + Xcode 16 或更高版本中执行。"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "安装 XcodeGen…"
    brew install xcodegen
  else
    echo "错误：没有找到 xcodegen。请先安装：brew install xcodegen"
    exit 1
  fi
fi

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"
cd "$ROOT"
xcodegen generate

echo "构建 $SCHEME ($CONFIGURATION)…"

if [[ -n "$TEAM_ID" ]]; then
  xcodebuild archive \
    -project GuanXing.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates
else
  xcodebuild archive \
    -project GuanXing.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGNING_ALLOWED=NO
fi

cat > "$ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST

if [[ -n "$TEAM_ID" ]]; then
  mkdir -p "$EXPORT_PATH"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$ROOT/build/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

  IPA_FILE="$(find "$EXPORT_PATH" -name '*.ipa' -maxdepth 1 | head -n 1 || true)"
  if [[ -n "$IPA_FILE" ]]; then
    cp "$IPA_FILE" "$ROOT/build/GuanXing.ipa"
    echo "完成：$ROOT/build/GuanXing.ipa"
  else
    echo "Archive 已完成，但未导出 IPA：$ARCHIVE_PATH"
    exit 1
  fi
else
  APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1 || true)"
  if [[ -z "$APP_PATH" ]]; then
    echo "Archive 中没找到 .app，已停止。"
    exit 1
  fi
  rm -rf "$ROOT/build/unsigned"
  mkdir -p "$ROOT/build/unsigned/Payload"
  cp -R "$APP_PATH" "$ROOT/build/unsigned/Payload/"
  (cd "$ROOT/build/unsigned" && zip -qry "$ROOT/build/GuanXing-unsigned.ipa" Payload)
  echo "未提供 DEVELOPMENT_TEAM，已生成未签名 IPA：$ROOT/build/GuanXing-unsigned.ipa"
  echo "该包需要用 AltStore / Sideloadly / 爱思助手重签后才能安装。"
fi
