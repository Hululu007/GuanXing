#!/usr/bin/env bash
set -euo pipefail

# 生成未签名 IPA，供 AltStore / Sideloadly / 爱思助手再次签名。
# 不含任何证书，不能直接双击安装，也不会绕过 iOS 签名。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null 2>&1 || { echo "请先安装 XcodeGen：brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "请在 macOS + Xcode 环境执行"; exit 1; }

xcodegen generate
rm -rf build/unsigned
mkdir -p build/unsigned/Payload

xcodebuild build \
  -project GuanXing.xcodeproj \
  -scheme GuanXing \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath build/derived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER=com.guanxing.player

APP_PATH="$(find build/derived/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -n 1)"
[[ -n "$APP_PATH" ]] || { echo "构建产物中没找到 .app"; exit 1; }

cp -R "$APP_PATH" build/unsigned/Payload/
cd build/unsigned
zip -qry ../GuanXing-unsigned.ipa Payload
cd "$ROOT"
echo "完成：$ROOT/build/GuanXing-unsigned.ipa"
