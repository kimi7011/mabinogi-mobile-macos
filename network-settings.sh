#!/bin/bash
# Only this fixed system configuration requires root. No executable is installed as root.
set -euo pipefail
label=io.github.kimi7011.mabinogi-mobile-macos.tcp
plist="/Library/LaunchDaemons/$label.plist"
target_value=1300000
action="${1:-}"
if [ "$action" != install ] && [ "$action" != remove ]; then
    echo 'Usage: sudo bash network-settings.sh install|remove' >&2
    exit 2
fi
if [ "$(/usr/bin/id -u)" != 0 ]; then
    echo '此操作需要管理員權限。' >&2
    exit 1
fi
valid_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
if [ -L "$plist" ]; then echo '拒絕使用符號連結設定檔。' >&2; exit 1; fi
if [ -e "$plist" ]; then
    # Refuse to replace or remove an unrelated file, even if it has the same name.
    [ "$(/usr/bin/stat -f %u "$plist")" = 0 ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")" = "$label" ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist")" = /usr/sbin/sysctl ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist")" = -w ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$plist")" = net.inet.tcp.sendspace=1300000 ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :RunAtLoad' "$plist")" = true ]
    original="$(/usr/libexec/PlistBuddy -c 'Print :MabinogiOriginalSendspace' "$plist")"
    valid_number "$original"
else
    if [ "$action" = remove ]; then echo '沒有此專案的開機設定，無需移除。'; exit 0; fi
    original="$(/usr/sbin/sysctl -n net.inet.tcp.sendspace)"
    valid_number "$original"
fi

if [ "$action" = install ]; then
    if [ ! -e "$plist" ]; then
        tmp="$(/usr/bin/mktemp /Library/LaunchDaemons/.mabinogi-mobile-tcp.XXXXXX)"
        trap '/bin/rm -f "$tmp"' EXIT
        /bin/cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/usr/sbin/sysctl</string><string>-w</string><string>net.inet.tcp.sendspace=$target_value</string></array>
<key>RunAtLoad</key><true/>
<key>MabinogiOriginalSendspace</key><integer>$original</integer>
</dict></plist>
EOF
        /usr/sbin/chown root:wheel "$tmp"
        /bin/chmod 0644 "$tmp"
        /usr/bin/plutil -lint "$tmp"
        /bin/mv "$tmp" "$plist"
        trap - EXIT
    fi
    /bin/launchctl enable "system/$label"
    if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
        /bin/launchctl kickstart "system/$label"
    else
        /bin/launchctl bootstrap system "$plist"
    fi
    for _attempt in 1 2 3 4 5; do
        if /bin/launchctl print "system/$label" | /usr/bin/grep -q 'last exit code = 0'; then
            [ "$(/usr/sbin/sysctl -n net.inet.tcp.sendspace)" = "$target_value" ]
            echo '開機自動設定已安裝，數值已驗證。'
            exit 0
        fi
        /bin/sleep 1
    done
    echo '開機項目未回報成功，請查看 launchctl print 的結果。' >&2
    exit 1
else
    if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
        /bin/launchctl bootout "system/$label"
    fi
    /bin/rm "$plist"
    if [ "$(/usr/sbin/sysctl -n net.inet.tcp.sendspace)" = "$target_value" ]; then
        /usr/sbin/sysctl -w "net.inet.tcp.sendspace=$original"
    else
        echo '目前數值已被其他設定變更，因此保留目前數值。'
    fi
    echo '已移除此專案的開機項目。'
fi
