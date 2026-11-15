#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
app="$HOME/Applications/瑪奇 Mobile 啟動.app"
echo '移除本專案的開機設定；CrossOver 容器、帳號與遊戲安裝資料會保留。'
/usr/bin/sudo /bin/bash "$project_dir/network-settings.sh" remove
if [ -d "$app" ]; then
    app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    if [ "$app_id" = io.github.kimi7011.mabinogi-mobile-macos ]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app"
        mkdir -p "$HOME/.Trash"
        trash_dir="$(mktemp -d "$HOME/.Trash/MabinogiMobileMac.XXXXXX")"
        mv "$app" "$trash_dir/瑪奇 Mobile 啟動.app"
        echo '啟動 App 已移到垃圾桶。'
    else
        echo '同名 App 不屬於此版本，已保留。'
    fi
fi
