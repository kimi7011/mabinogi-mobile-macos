#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
target_dir="$HOME/Applications"
keep_network=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app-dir)
            [ "$#" -ge 2 ] && [[ "$2" = /* ]] || { echo '--app-dir 需要絕對路徑。' >&2; exit 2; }
            target_dir="$2"; shift 2 ;;
        --keep-network) keep_network=true; shift ;;
        *) echo 'Usage: bash uninstall.command [--app-dir /absolute/path] [--keep-network]' >&2; exit 2 ;;
    esac
done
app="$target_dir/瑪奇 Mobile 啟動.app"
echo '移除本專案的開機設定；CrossOver 容器、帳號與遊戲安裝資料會保留。'
if ! $keep_network; then /usr/bin/sudo /bin/bash "$project_dir/network-settings.sh" remove; fi
if [ -L "$app" ]; then echo '目標 App 是符號連結，已保留。' >&2; exit 1; fi
if [ -d "$app" ]; then
    app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    if [ "$app_id" = io.github.kimi7011.mabinogi-mobile-macos ]; then
        "$app/Contents/MacOS/NexonBridge" --restore-handler
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app"
        mkdir -p "$HOME/.Trash"
        trash_dir="$(mktemp -d "$HOME/.Trash/MabinogiMobileMac.XXXXXX")"
        mv "$app" "$trash_dir/瑪奇 Mobile 啟動.app"
        echo '啟動 App 已移到垃圾桶。'
    else
        echo '同名 App 不屬於此版本，已保留。'
    fi
fi
