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
        *) echo 'Usage: bash install.command [--app-dir /absolute/path] [--keep-network]' >&2; exit 2 ;;
    esac
done
app_name='瑪奇 Mobile 啟動.app'
source_app="$project_dir/$app_name"
if [ ! -d "$source_app" ]; then
    source_app="$project_dir/dist/$app_name"
    if [ ! -d "$source_app" ]; then /bin/bash "$project_dir/build.sh"; fi
fi
/usr/bin/codesign --verify --deep --strict "$source_app"
target_app="$target_dir/$app_name"
mkdir -p "$target_dir"
if [ -L "$target_app" ]; then echo '目標 App 是符號連結，已保留。' >&2; exit 1; fi
if [ -e "$target_app" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
    case "$existing_id" in
        io.github.kimi7011.mabinogi-mobile-macos) ;;
        local.kimi.mabinogi-crossover-bridge)
            echo '已保留原修復入口。請以 --app-dir 指定另一個安裝資料夾。' >&2; exit 1 ;;
        *) echo '目標位置有其他程式，請先自行更名。' >&2; exit 1 ;;
    esac
fi
"$source_app/Contents/MacOS/NexonBridge" --remember-handler
stage="$(mktemp -d "$target_dir/.mabinogi-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$source_app" "$stage/$app_name"
/usr/bin/codesign --verify --deep --strict "$stage/$app_name"
if $keep_network; then
    current_value="$(/usr/sbin/sysctl -n net.inet.tcp.sendspace)"
    if ! [[ "$current_value" =~ ^[0-9]+$ ]] || [ "$current_value" -lt 1000000 ]; then
        echo '既有 TCP 設定不足，不能使用 --keep-network。' >&2; exit 1
    fi
    echo '保留既有網路設定；本次不新增或修改開機項目。請確保既有設定會在開機後生效。'
else
    echo '安裝開機相容設定，需要一次管理員驗證。密碼不會顯示或保存。'
    /usr/bin/sudo /bin/bash "$project_dir/network-settings.sh" install
fi
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
