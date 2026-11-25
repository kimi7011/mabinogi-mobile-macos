#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${1:-$project_dir/dist}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    echo '請先安裝 Apple Command Line Tools：xcode-select --install' >&2
    exit 1
fi
stage="$(mktemp -d "$build_dir/.mabinogi-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/瑪奇 Mobile 啟動.app"
mkdir -p "$app/Contents/MacOS" "$stage/module-cache"
cp "$project_dir/Info.plist" "$app/Contents/Info.plist"
if [ -n "${MABINOGI_ICON_PATH:-}" ]; then
    /usr/bin/iconutil -c iconset -o "$stage/CustomIcon.iconset" "$MABINOGI_ICON_PATH"
    mkdir -p "$app/Contents/Resources"
    cp "$MABINOGI_ICON_PATH" "$app/Contents/Resources/CustomIcon.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string CustomIcon.icns' "$app/Contents/Info.plist"
fi
arch="$(/usr/bin/uname -m)"
case "$arch" in arm64|x86_64) ;; *) echo '不支援此處理器架構。' >&2; exit 1 ;; esac
/usr/bin/xcrun swiftc -swift-version 5 -O -target "${arch}-apple-macosx12.0" \
    -module-cache-path "$stage/module-cache" -framework AppKit \
    "$project_dir/NexonBridge.swift" -o "$app/Contents/MacOS/NexonBridge"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/NexonBridge" --self-test
if [ -e "$build_dir/瑪奇 Mobile 啟動.app" ]; then
    echo '輸出位置已有 App，請改用新的輸出資料夾。' >&2
    exit 1
fi
mv "$app" "$build_dir/瑪奇 Mobile 啟動.app"
echo "建置完成：$build_dir/瑪奇 Mobile 啟動.app"
