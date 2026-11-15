#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
app_name='瑪奇 Mobile 啟動.app'
source_app="$project_dir/$app_name"
if [ ! -d "$source_app" ]; then
    source_app="$project_dir/dist/$app_name"
    if [ ! -d "$source_app" ]; then /bin/bash "$project_dir/build.sh"; fi
fi
/usr/bin/codesign --verify --deep --strict "$source_app"
target_dir="$HOME/Applications"
target_app="$target_dir/$app_name"
mkdir -p "$target_dir"
if [ -e "$target_app" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
    case "$existing_id" in
        io.github.kimi7011.mabinogi-mobile-macos|local.kimi.mabinogi-crossover-bridge) ;;
        *) echo '目標位置有其他程式，請先自行更名。' >&2; exit 1 ;;
    esac
fi
stage="$(mktemp -d "$target_dir/.mabinogi-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$source_app" "$stage/$app_name"
/usr/bin/codesign --verify --deep --strict "$stage/$app_name"
echo '安裝開機相容設定，需要一次管理員驗證。密碼不會顯示或保存。'
/usr/bin/sudo /bin/bash "$project_dir/network-settings.sh" install
if [ -e "$target_app" ]; then
    backup_dir="$HOME/Library/Application Support/MabinogiMobileMac/backups"
    mkdir -p "$backup_dir"
    backup="$(mktemp -d "$backup_dir/app.XXXXXX")"
    mv "$target_app" "$backup/$app_name"
    echo "舊入口已備份：$backup/$app_name"
fi
mv "$stage/$app_name" "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
echo "安裝完成，請開啟：$target_app"
echo '第一次仍需在 CrossOver 安裝官方 Nexon Launcher，登入並下載遊戲。'
