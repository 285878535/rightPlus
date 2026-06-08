#!/bin/bash
#
# RightPlus 轻量发版脚本（无需签名 / 公证）
# 用法：  ./scripts/release.sh 1.1
#
# 发版前：在 Xcode 把 MARKETING_VERSION（和 CURRENT_PROJECT_VERSION）调高
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/release.sh <版本号>，如 1.1}"
APP="RightPlus"
SCHEME="rightMousePlus"
PROJECT="rightMousePlus.xcodeproj"

BUILD="build/release"
ARCHIVE="$BUILD/$APP.xcarchive"
DIST="dist"
rm -rf "$BUILD"; mkdir -p "$BUILD" "$DIST"

echo "▶︎ 1/2 归档（Release）"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" archive

echo "▶︎ 2/2 打包 zip"
ZIP="$DIST/$APP-$VERSION.zip"
ditto -c -k --keepParent "$ARCHIVE/Products/Applications/$APP.app" "$ZIP"

cat <<EOF

✅ 完成：$ZIP
接下来：
  1. GitHub 建 release，tag = v${VERSION}，上传：$ZIP
  2. 改 update.json 的 version 为 ${VERSION}（notes 可选），提交：
       git add update.json && git commit -m "release ${VERSION}" && git push
  3. 清 jsDelivr 缓存：
       https://purge.jsdelivr.net/gh/285878535/rightPlus@main/update.json
  朋友打开 App 即收到「发现新版本」提示，点「前往下载」即可。
  （未签名/公证：首次打开需右键 → 打开，绕过 Gatekeeper 一次）
EOF
