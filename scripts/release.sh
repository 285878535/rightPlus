#!/bin/bash
#
# RightPlus 发版脚本
# 用法：  ./scripts/release.sh 1.1
#
# 前置（一次性）：
#   1. 已安装「Developer ID Application」证书（付费账号，从开发者网站下载到钥匙串）
#   2. 配置公证凭证（一次性）：
#        xcrun notarytool store-credentials RightPlusNotary \
#          --apple-id "你的AppleID" --team-id 268ZU2CHQ8 --password "App专用密码"
#   3. 已用 generate_keys 生成 EdDSA 私钥（已在钥匙串里）
#
# 发版前：在 Xcode 把 MARKETING_VERSION 和 CURRENT_PROJECT_VERSION 都调高
#         （Sparkle 主要按 CURRENT_PROJECT_VERSION / CFBundleVersion 判断新旧）
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/release.sh <版本号>，如 1.1}"
APP="RightPlus"
SCHEME="rightMousePlus"
PROJECT="rightMousePlus.xcodeproj"
TEAM_ID="268ZU2CHQ8"
NOTARY_PROFILE="RightPlusNotary"
DOWNLOAD_PREFIX="https://github.com/285878535/rightPlus/releases/download/v${VERSION}/"

BUILD="build/release"
ARCHIVE="$BUILD/$APP.xcarchive"
EXPORT="$BUILD/export"
DIST="dist"
rm -rf "$BUILD"; mkdir -p "$BUILD" "$DIST"

echo "▶︎ 1/5 归档（Release）"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" archive

echo "▶︎ 2/5 导出 Developer ID 签名版"
cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" -exportOptionsPlist "$BUILD/ExportOptions.plist"

ZIP="$DIST/$APP-$VERSION.zip"
echo "▶︎ 3/5 公证"
ditto -c -k --keepParent "$EXPORT/$APP.app" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶︎ 4/5 装订(staple)并重新打包"
xcrun stapler staple "$EXPORT/$APP.app"
rm -f "$ZIP"
ditto -c -k --keepParent "$EXPORT/$APP.app" "$ZIP"

echo "▶︎ 5/5 生成 appcast.xml（EdDSA 签名）"
GEN=$(find "$HOME/Library/Developer/Xcode/DerivedData/rightMousePlus-"*/SourcePackages/artifacts/sparkle/Sparkle/bin -name generate_appcast 2>/dev/null | head -1)
"$GEN" "$DIST" --download-url-prefix "$DOWNLOAD_PREFIX"
cp "$DIST/appcast.xml" appcast.xml

cat <<EOF

✅ 完成。接下来：
  1. 在 GitHub 建 release  tag = v${VERSION}，上传：  $ZIP
  2. 提交 appcast.xml：  git add appcast.xml && git commit -m "release ${VERSION}" && git push
  3. 清 jsDelivr 缓存：  https://purge.jsdelivr.net/gh/285878535/rightPlus@main/appcast.xml
  老用户打开 App 即自动收到更新。
EOF
