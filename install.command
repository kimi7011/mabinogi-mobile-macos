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
app_id='io.github.kimi7011.mabinogi-mobile-macos'
backup_dir="$HOME/Library/Application Support/MabinogiMobileMac/backups"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
target_app="$target_dir/$app_name"
mkdir -p "$target_dir"
if [ -L "$target_app" ]; then echo '目標 App 是符號連結，已保留。' >&2; exit 1; fi
if [ -e "$target_app" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
    case "$existing_id" in
        "$app_id") ;;
        local.kimi.mabinogi-crossover-bridge)
            echo '已保留原修復入口。請以 --app-dir 指定另一個安裝資料夾。' >&2; exit 1 ;;
        *) echo '目標位置有其他程式，請先自行更名。' >&2; exit 1 ;;
    esac
fi
stage="$(mktemp -d "$target_dir/.mabinogi-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
payload="$project_dir/launcher-payload.zip"
if [ -f "$payload" ]; then
    /usr/bin/ditto -x -k "$payload" "$stage/payload"
    source_app="$stage/payload/$app_name"
else
    source_app="$project_dir/$app_name"
    if [ ! -d "$source_app" ]; then
        source_app="$project_dir/dist/$app_name"
        if [ ! -d "$source_app" ]; then /bin/bash "$project_dir/build.sh"; fi
    fi
fi
[[ -d "$source_app" && ! -L "$source_app" ]] || { echo '找不到有效的安裝 App。' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_app"
source_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")"
[[ "$source_id" == "$app_id" ]] || { echo '安裝 App 的識別碼不符。' >&2; exit 1; }
"$source_app/Contents/MacOS/NexonBridge" --remember-handler
/usr/bin/ditto "$source_app" "$stage/$app_name"
/usr/bin/codesign --verify --deep --strict "$stage/$app_name"

backup_app() {
    local app="$1" backup verification pending archive
    mkdir -p "$backup_dir" || return 1
    verification="$(mktemp -d "$stage/verify.XXXXXX")" || return 1
    backup="$(mktemp -d "$backup_dir/app.XXXXXX")" || return 1
    pending="$backup/.archive.zip"
    archive="$backup/${app_name%.app}.zip"
    if ! /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$pending" ||
       ! /usr/bin/ditto -x -k "$pending" "$verification" ||
       ! /usr/bin/codesign --verify --deep --strict "$verification/$app_name" ||
       ! /usr/bin/diff -qr "$app" "$verification/$app_name" ||
       ! mv "$pending" "$archive"; then
        rm -f "$pending"
        rmdir "$backup"
        return 1
    fi
    echo "舊入口已備份：$archive"
}

# Older installers left runnable bundles that could register for nxl://.
archive_legacy_backups() {
    local app parent legacy_id retired
    for app in "$backup_dir"/app.*/"$app_name"; do
        parent="${app%/*}"
        [[ -d "$app" && ! -L "$app" && ! -L "$parent" ]] || continue
        [[ ! "$app" -ef "$target_app" ]] || continue
        legacy_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" || continue
        [[ "$legacy_id" == "$app_id" ]] || continue
        if ! /usr/bin/codesign --verify --deep --strict "$app" || ! backup_app "$app"; then
            echo "舊備份無法驗證，已保留：$app" >&2
            continue
        fi
        retired="$(mktemp -d "$stage/retired.XXXXXX")" || return 1
        "$lsregister" -u "$app" || true
        if ! mv "$app" "$retired/previous"; then
            echo "無法停用舊備份：$app" >&2
            return 1
        fi
        rmdir "$parent" 2>/dev/null || true
    done
}

if [ -e "$target_app" ]; then backup_app "$target_app"; fi
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
archive_legacy_backups
if [ -e "$target_app" ]; then
    "$lsregister" -u "$target_app" || true
    if ! mv "$target_app" "$stage/previous"; then
        "$lsregister" -f "$target_app"
        exit 1
    fi
fi
if mv "$stage/$app_name" "$target_app"; then
    if "$lsregister" -f "$target_app"; then
        echo "安裝完成，請開啟：$target_app"
        echo '第一次仍需在 CrossOver 安裝官方 Nexon Launcher，登入並下載遊戲。'
        exit 0
    fi
    "$lsregister" -u "$target_app" || true
    mv "$target_app" "$stage/failed"
fi
if [ -d "$stage/previous" ] && [ ! -e "$target_app" ]; then
    mv "$stage/previous" "$target_app"
    "$lsregister" -f "$target_app"
fi
echo '無法完成 App 安裝。' >&2
exit 1
