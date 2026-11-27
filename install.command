#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
target_dir="$HOME/Applications"
keep_network=false
no_launch=false
cask_stage=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --app-dir)
            [ "$#" -ge 2 ] && [[ "$2" = /* ]] || { echo '--app-dir 需要絕對路徑。' >&2; exit 2; }
            target_dir="$2"; shift 2 ;;
        --keep-network) keep_network=true; shift ;;
        --no-launch) no_launch=true; shift ;;
        --cask-stage)
            [ "$#" -ge 2 ] && [[ "$2" = /* ]] || { echo '--cask-stage 需要絕對路徑。' >&2; exit 2; }
            cask_stage="$2"; shift 2 ;;
        *) echo '用法：bash 安裝指令 [--app-dir /absolute/path] [--keep-network] [--no-launch]' >&2; exit 2 ;;
    esac
done
app_name='瑪奇 Mobile 啟動.app'
app_id='io.github.kimi7011.mabinogi-mobile-macos'
backup_dir="$HOME/Library/Application Support/MabinogiMobileMac/backups"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
support_dir="$project_dir"
modern_package=false
if [ -e "$project_dir/Support" ] || [ -L "$project_dir/Support" ]; then
    support_dir="$project_dir/Support"
    modern_package=true
    if [ ! -f "$support_dir/launcher-payload.zip" ] || { ! $keep_network && [ ! -f "$support_dir/network-settings.sh" ]; }; then
        echo '安裝包不完整，請完整解壓縮下載的 ZIP，再從解壓縮後的資料夾執行安裝。' >&2
        exit 1
    fi
fi
payload="$support_dir/launcher-payload.zip"
target_app="$target_dir/$app_name"
if [ -n "$cask_stage" ]; then
    [[ -d "$cask_stage" && ! -L "$cask_stage" && ! -L "$cask_stage/$app_name" ]] ||
        { echo 'Homebrew App 暫存位置無效。' >&2; exit 1; }
    [[ -f "$payload" ]] || { echo 'Homebrew 安裝包不完整。' >&2; exit 1; }
else
    mkdir -p "$target_dir"
fi
if [ -L "$target_app" ]; then echo '目標 App 是符號連結，已保留。' >&2; exit 1; fi
if [ -e "$target_app" ] && { [ -z "$cask_stage" ] || [ -f "$target_app/Contents/Info.plist" ]; }; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
    case "$existing_id" in
        "$app_id") ;;
        local.kimi.mabinogi-crossover-bridge)
            echo '已保留原修復入口。請以 --app-dir 指定另一個安裝資料夾。' >&2; exit 1 ;;
        *) echo '目標位置有其他程式，請先自行更名。' >&2; exit 1 ;;
    esac
fi
stage="$(mktemp -d "${cask_stage:-$target_dir}/.mabinogi-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
if [ -f "$payload" ]; then
    /usr/bin/ditto -x -k "$payload" "$stage/payload"
    source_app="$stage/payload/$app_name"
else
    source_app="$project_dir/$app_name"
    if [ ! -d "$source_app" ]; then
        source_app="$project_dir/dist/$app_name"
        if [ ! -d "$source_app" ]; then
            if [ ! -f "$project_dir/build.sh" ]; then
                echo '找不到安裝檔，請完整解壓縮下載的 ZIP。' >&2
                exit 1
            fi
            /bin/bash "$project_dir/build.sh"
        fi
    fi
fi
[[ -d "$source_app" && ! -L "$source_app" ]] || { echo '找不到有效的安裝 App。' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$source_app"
source_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")"
[[ "$source_id" == "$app_id" ]] || { echo '安裝 App 的識別碼不符。' >&2; exit 1; }
if [ -n "$cask_stage" ] && [ -e "$cask_stage/$app_name" ]; then
    # Homebrew can restore an already prepared App while reverting an upgrade.
    restored_app="$cask_stage/$app_name"
    /usr/bin/codesign --verify --deep --strict "$restored_app"
    restored_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$restored_app/Contents/Info.plist")"
    restored_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$restored_app/Contents/Info.plist")"
    source_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_app/Contents/Info.plist")"
    [[ "$restored_id" == "$app_id" && "$restored_version" == "$source_version" ]] ||
        { echo 'Homebrew 暫存 App 的識別碼或版本不符。' >&2; exit 1; }
    exit 0
fi
staged_app="$stage/$app_name"
/usr/bin/ditto "$source_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

download_official_file() {
    local url="$1" output="$2" max_size="$3" size
    /usr/bin/curl --disable --fail --silent --show-error --proto '=https' \
        --connect-timeout 8 --max-time 20 --retry 2 --retry-max-time 30 --max-filesize "$max_size" \
        --output "$output" "$url" || return 1
    size="$(/usr/bin/stat -f %z "$output")" || return 1
    [[ "$size" -gt 0 && "$size" -le "$max_size" ]]
}

render_official_icon() {
    local url="$1" name="$2"
    local image="$stage/$name" iconset="$stage/$name.iconset"
    download_official_file "$url" "$image" 4194304 || return 1
    /bin/mkdir "$iconset" || return 1

    # ImageIO and CoreGraphics ship with macOS and work before the App has been opened.
    /usr/bin/osascript -l JavaScript - "$image" "$iconset" <<'JAVASCRIPT' || return 1
ObjC.import('Foundation');
ObjC.import('ImageIO');
ObjC.import('CoreGraphics');

function run([input, output]) {
    const invalidArtwork = '圖示來源須是邊長 512 至 2048 像素的單張正方形 PNG、JPEG 或 WebP。';
    const data = $.NSData.dataWithContentsOfFile(input);
    const length = Number(data.length);
    if (!(length >= 12)) {
        throw new Error(invalidArtwork);
    }
    const source = $.CGImageSourceCreateWithData(data, null);
    if (Number($.CGImageSourceGetCount(source)) !== 1 ||
        Number($.CGImageSourceGetStatus(source)) !== Number($.kCGImageStatusComplete)) {
        throw new Error(invalidArtwork);
    }
    const type = ObjC.unwrap(ObjC.castRefToObject($.CGImageSourceGetType(source)));
    if (!['public.png', 'public.jpeg', 'org.webmproject.webp'].includes(type)) {
        throw new Error(invalidArtwork);
    }
    if (type === 'public.png') {
        // ImageIO may decode a partial PNG even when its final IEND chunk is missing.
        const trailer = data.subdataWithRange($.NSMakeRange(length - 12, 12));
        if (ObjC.unwrap(trailer.base64EncodedStringWithOptions(0)) !== 'AAAAAElFTkSuQmCC') {
            throw new Error(invalidArtwork);
        }
    }
    const properties = ObjC.castRefToObject($.CGImageSourceCopyPropertiesAtIndex(source, 0, null));
    const width = ObjC.unwrap(properties.objectForKey(ObjC.castRefToObject($.kCGImagePropertyPixelWidth)));
    const height = ObjC.unwrap(properties.objectForKey(ObjC.castRefToObject($.kCGImagePropertyPixelHeight)));
    if (!Number.isInteger(width) || width < 512 || width > 2048 || width !== height) {
        throw new Error(invalidArtwork);
    }
    const artwork = $.CGImageSourceCreateImageAtIndex(source, 0, null);
    if (Number($.CGImageGetWidth(artwork)) !== width || Number($.CGImageGetHeight(artwork)) !== height) {
        throw new Error(invalidArtwork);
    }

    const colorSpace = $.CGColorSpaceCreateWithName($.kCGColorSpaceSRGB);
    for (const size of [16, 32, 128, 256, 512]) {
        for (const [scale, suffix] of [[1, ''], [2, '@2x']]) {
            const side = size * scale;
            const context = $.CGBitmapContextCreate(null, side, side, 8, side * 4, colorSpace,
                                                    $.kCGImageAlphaPremultipliedLast);
            if (Number($.CGBitmapContextGetWidth(context)) !== side) {
                throw new Error('無法產生 macOS 圖示。');
            }
            const extent = side * 0.8046875;
            const inset = (side - extent) / 2;
            const radius = extent * 0.21;
            const box = $.CGRectMake(inset, inset, extent, extent);
            $.CGContextSetAllowsAntialiasing(context, true);
            $.CGContextSetShouldAntialias(context, true);
            $.CGContextSetInterpolationQuality(context, $.kCGInterpolationHigh);
            $.CGContextAddPath(context, $.CGPathCreateWithRoundedRect(box, radius, radius, null));
            $.CGContextClip(context);
            $.CGContextDrawImage(context, box, artwork);

            const path = output + '/icon_' + size + 'x' + size + suffix + '.png';
            const png = $.CGImageDestinationCreateWithURL($.NSURL.fileURLWithPath(path), $('public.png'), 1, null);
            $.CGImageDestinationAddImage(png, $.CGBitmapContextCreateImage(context), null);
            if (!$.CGImageDestinationFinalize(png)) {
                throw new Error('無法產生 macOS 圖示。');
            }
        }
    }
}
JAVASCRIPT
    /usr/bin/iconutil -c icns -o "$stage/$name.icns" "$iconset" &&
        mv "$stage/$name.icns" "$stage/MabinogiOfficial.icns"
}

fetch_official_icon() {
    local lookup_url='https://itunes.apple.com/lookup?id=6759030432&country=tw'
    local artwork_pattern='^https://is[0-9]+-ssl\.mzstatic\.com/image/thumb/([A-Za-z0-9_-][A-Za-z0-9_.-]*/)+[0-9]{2,4}x[0-9]{2,4}bb\.(jpg|jpeg|png|webp)$'
    local lookup="$stage/app-store.json" track_id bundle_id artwork_url

    echo '正在查詢 Apple App Store 最新的瑪奇 Mobile 圖示。'
    if ! download_official_file "$lookup_url" "$lookup" 1048576; then
        echo '無法查詢台灣 App Store 的圖示。' >&2
        return 1
    fi
    if ! track_id="$(/usr/bin/plutil -extract results.0.trackId raw -o - "$lookup" 2>/dev/null)" ||
       ! bundle_id="$(/usr/bin/plutil -extract results.0.bundleId raw -o - "$lookup" 2>/dev/null)" ||
       ! artwork_url="$(/usr/bin/plutil -extract results.0.artworkUrl512 raw -o - "$lookup" 2>/dev/null)" ||
       [[ "$track_id" != 6759030432 || "$bundle_id" != com.nexon.devcat.mm.tw || ! "$artwork_url" =~ $artwork_pattern ]]; then
        echo '無法驗證台灣 App Store 的瑪奇 Mobile 圖示來源。' >&2
        return 1
    fi
    if render_official_icon "${artwork_url%/*}/1024x1024bb.png" app-store-large ||
       render_official_icon "$artwork_url" app-store-original; then
        return 0
    fi
    echo '無法使用 App Store 提供的圖示檔案。' >&2
    return 1
}

previous_official_icon() {
    local resources="$target_app/Contents/Resources" file key
    file="$resources/MabinogiOfficial.icns"
    [[ -f "$file" && ! -L "$resources" && ! -L "$file" ]] || return 1
    key="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$target_app/Contents/Info.plist" 2>/dev/null)" || return 1
    [[ "$key" == MabinogiOfficial.icns ]] &&
        /usr/bin/codesign --verify --deep --strict "$target_app" &&
        /usr/bin/ditto "$file" "$stage/MabinogiOfficial.icns"
}

attach_official_icon() {
    local resources="$staged_app/Contents/Resources"
    [[ ! -L "$resources" && ! -L "$resources/MabinogiOfficial.icns" ]] || return 1
    mkdir -p "$resources"
    mv "$stage/MabinogiOfficial.icns" "$resources/MabinogiOfficial.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string MabinogiOfficial.icns' "$staged_app/Contents/Info.plist"
    /usr/bin/codesign --force --sign - "$staged_app"
    /usr/bin/codesign --verify --deep --strict "$staged_app"
}

if [ -f "$payload" ] && ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$staged_app/Contents/Info.plist" >/dev/null 2>&1; then
    if fetch_official_icon; then
        attach_official_icon
    elif previous_official_icon; then
        echo '已保留上次安裝的官方圖示，繼續安裝。'
        attach_official_icon
    else
        echo '暫用 macOS 預設圖示，繼續安裝。重跑安裝程式時會再嘗試下載官方圖示。'
    fi
fi
if [ -n "$cask_stage" ]; then
    # Homebrew owns the installed app and moves the staged bundle itself.
    mv "$staged_app" "$cask_stage/$app_name"
    exit 0
fi
# Registration can change an implicit nxl:// handler. Save the original choice
# using LaunchServices before installing and opening the downloaded App.
/usr/bin/osascript -l JavaScript - "$app_id" <<'JXA'
ObjC.import('AppKit')
function run([identifier]) {
    const preferences = $.NSUserDefaults.alloc.initWithSuiteName(identifier)
    if (!preferences.stringForKey('PreviousNXLHandlerPath').isNil()) return
    const url = $.NSURL.URLWithString('nxl://play/59826')
    const previous = $.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(url)
    if (previous.isNil()) return
    if (ObjC.unwrap($.NSBundle.bundleWithURL(previous).bundleIdentifier) !== identifier) {
        preferences.setObjectForKey(previous.path, 'PreviousNXLHandlerPath')
        if (!preferences.synchronize) throw Error('無法儲存原本的 Nexon 連結處理程式。')
    }
}
JXA

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
    /usr/bin/sudo /bin/bash "$support_dir/network-settings.sh" install
fi
archive_legacy_backups
if [ -e "$target_app" ]; then
    "$lsregister" -u "$target_app" || true
    if ! mv "$target_app" "$stage/previous"; then
        "$lsregister" -f "$target_app"
        exit 1
    fi
fi
if mv "$staged_app" "$target_app"; then
    if "$lsregister" -f "$target_app"; then
        if $modern_package && ! $no_launch; then
            echo "安裝完成：$target_app"
            echo '若 macOS 無法驗證開發者，請確認下載來源後，到「系統設定 → 隱私權與安全性」為這個 App 選「強制打開」。'
            if ! /usr/bin/open "$target_app"; then
                echo "無法自動開啟，請手動開啟：$target_app" >&2
            fi
        else
            echo "安裝完成，請開啟：$target_app"
        fi
        echo '首次遊玩需在 CrossOver 安裝官方 Nexon Launcher，再登入並下載遊戲。'
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
