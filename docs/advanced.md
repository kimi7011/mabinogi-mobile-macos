# 進階說明

第一次安裝、更新方式與本機運行狀態請見 [README](../README.md)。

## 啟動器和容器

- 安裝器預設將 App 放在 `~/Applications/瑪奇 Mobile 啟動.app`。原修復入口若使用另一個 bundle ID，可用下方指令安裝到獨立資料夾。
- 容器位於外接磁碟時，先掛載磁碟。macOS 詢問「卸除式卷宗」存取時，請允許啟動器存取存放容器的磁碟。
- 此安裝包使用 ad-hoc 簽章。若 macOS 阻擋，確認檔案來自本專案後，依系統提供的個別 App 開啟方式處理。
- 登入後可在 Nexon「啟動器設定 → 一般 → 安全性」開啟自動登入。之後使用帳號選單的「離開」結束 Nexon，讓相同容器下次讀取既有登入狀態。

```sh
bash install.command --app-dir "$HOME/Applications/MabinogiMobileMac"
```

先結束遊戲與 Nexon，再重新選擇容器。若安裝在其他資料夾，請改用實際的 App 路徑。

```sh
open -n "$HOME/Applications/瑪奇 Mobile 啟動.app" --args --choose-bottle
```

## DXMT 與遊玩閃退

v0.1.4 在支援的環境中，會在啟動台灣版瑪奇（遊戲代號 59826）前，為選定的容器套用 DXMT。圖形設定套用到同一容器內的 Windows 程式，因此建議使用瑪奇專用容器。[CodeWeavers 圖形設定](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac-26) · [DXMT 系統需求](https://github.com/3Shain/dxmt/wiki/Device-System-Runtime-Specifications)

Apple M6、macOS 27.0.1、CrossOver 26.3 的對照測試中，原本的 D3DMetal 在換圖或切回遊戲時重現 `BlackCall64.aes` 的 `0xC0000005`。改為視窗模式或停用 MSync 也重現過。切到 DXMT 後，沿用原本的無邊框模式及 MSync 測試超過一小時，未再重現同一閃退。這是一台 Mac 的實測結果。

## 常見問題

- **看不到 Nexon 視窗或登入畫面黑屏**。等 Nexon 首次更新完成，離開啟動器後再用本專案的 App 開啟。若 Nexon 仍在背景，請先離開遊戲，再由 CrossOver 結束該容器內的程式。
- **Facebook 顯示返回啟動器，遊戲沒有啟動**。切回 Nexon 視窗，完成可能出現的電子郵件驗證。若登入逾時，從同一個 Nexon 視窗建立新的登入流程。
- **遊戲更新後無法啟動**。在原容器開啟官方 Nexon Launcher 完成更新，再用本專案的 App 啟動。
- **CrossOver 匯出遊戲捷徑時閃退**。先更新啟動工具。若仍在 `exportProgram` 或 `updateApplicationFolder` 發生錯誤，正常離開該容器的程式，再重建捷徑。

```sh
bottle_folder="$(defaults read com.codeweavers.CrossOver BottleDir 2>/dev/null || true)"
if [ -z "$bottle_folder" ]; then
    bottle_folder="$HOME/Library/Application Support/CrossOver/Bottles"
fi
CX_BOTTLE_PATH="$bottle_folder" \
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/cxmenu" \
    --scope private --bottle "Mabinogi Mobile" --install
```

請把 `Mabinogi Mobile` 換成實際容器名稱。若 CrossOver 安裝在其他位置，請使用它的實際路徑。

## 網路設定與登入回傳

安裝器會用 LaunchDaemon 在 Mac 開機時將 `net.inet.tcp.sendspace` 設為 `1300000`，供 CrossOver 下載時使用。這個數值影響整台 Mac。移除時會依安裝前記錄的值還原。已由管理員維持至少 `1000000` 時，可使用 `install.command --keep-network`，日後移除也須使用 `uninstall.command --keep-network`。[ZeroMQ 的 Wine 說明](https://github.com/zeromq/libzmq/blob/master/INSTALL)

下載若一直停在驗證中，可用 `sysctl net.inet.tcp.sendspace` 確認目前數值。系統啟動項目為 `io.github.kimi7011.mabinogi-mobile-macos.tcp`。

`nxl://` 是 Nexon 共用的登入與啟動連結。選擇此工具作為處理程式後，系統會把連結交給選定的容器。移除工具時，若原處理程式還在，會還原對應。移除工具會保留 CrossOver 容器與遊戲。更新前的 App 備份位於 `~/Library/Application Support/MabinogiMobileMac/backups/`。

## 從原始碼建置

安裝 Apple Command Line Tools，再從專案目錄執行。

```sh
bash build.sh
python3 test.py "dist/瑪奇 Mobile 啟動.app"
"dist/瑪奇 Mobile 啟動.app/Contents/MacOS/NexonBridge" --check
```

`build.sh` 會建置並驗證 App 簽章與自我測試。`test.py` 使用暫存資料夾與模擬的系統命令測試安裝、重複安裝、移除和設定保護。`--check` 可查看 CrossOver、容器、TCP buffer 與 DXMT 的可用狀態。

回報問題時請提供機型、macOS／CrossOver 版本、發生時間與操作。上傳畫面或紀錄前請遮蔽帳號與登入資訊。
