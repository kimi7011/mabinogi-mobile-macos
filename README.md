# 瑪奇 Mobile × macOS / CrossOver

讓台灣版《瑪奇 Mobile》的 Nexon Launcher 在 macOS / CrossOver 下完成登入、下載與啟動的輕量工具。

**[下載安裝包](https://github.com/kimi7011/mabinogi-mobile-macos/raw/refs/heads/main/MabinogiMobileMac-arm64.zip)** · [SHA-256](SHA256SUMS.txt) · [回報問題](https://github.com/kimi7011/mabinogi-mobile-macos/issues) · [MIT 授權](LICENSE)

原先手動修復的環境已在 Apple M1、16 GB 記憶體、macOS 27.2、CrossOver 26.1 上完成 Facebook 登入、官方遊戲下載及啟動；使用者確認到達遊戲登入／伺服器選擇畫面。日期為 2026-11-16。這是社群相容工具，並非 Nexon 或 CodeWeavers 官方的 macOS 版本。

**公開安裝包已完成隔離環境的首次安裝、登入與遊戲啟動實測。** 已實際從 GitHub 下載安裝包並驗證 SHA-256，在全新容器安裝與更新官方 Nexon，完成 Facebook 登入及 Nexon 電子郵件帳戶驗證，再由官方啟動器驗證 APFS 獨立副本中的遊戲資源。使用下載包內的入口後，已直接觀察到 QA 遊戲的伺服器選擇與「開始遊戲」畫面；這次從點入口到建立遊戲程序約 13 秒。遊戲資源未在新容器重新完整下載，因此此項不列為重新下載全部資源的驗證。

**自動登入與重新啟動亦已實測通過。** 在 Nexon 的啟動器設定啟用「自動登入」，以帳號選單「離開」正常結束後，再開下載包的入口；未再次操作 Facebook，約 15 秒後建立遊戲程序，並到達原生遊戲的選服／開始遊戲畫面。這次測試關閉了遠端診斷功能。

下載包也已完成獨立位置安裝、重複安裝與移除；移除後已實測還原原本的登入連結處理程式。公開版網路設定已完成實際管理員安裝、執行及移除。隔離測試期間，原入口、原開機項目、TCP 數值、原容器登錄檔與 1,177 個遊戲檔案均經比對保持不變。

安裝包固定使用相同檔名；後續修正直接更新此檔案與說明。

## 第一次安裝

1. 安裝並啟用 [CodeWeavers CrossOver](https://www.codeweavers.com/crossover)。本專案不包含 CrossOver 授權。
2. 在 CrossOver 建立 **Windows 10 64 位元**容器，建議命名 **`Mabinogi Mobile`**。下載 [Nexon 官方 Windows 台灣版安裝器](https://download.nxfs.nexon.com/download-launcher?file=NexonLauncherSetup_TW.exe&product-id=59826)，在 CrossOver 選擇將它安裝到剛建立的容器。檔名應為 **`NexonLauncherSetup_TW.exe`**；Nexon 首頁可能依 Mac 瀏覽器轉往其他遊戲的 `.pkg`，請勿使用該檔案。官方遊戲資訊見[下載與配備頁](https://tw.nexon.com/mabinogimobile/home/support/download)。
3. 安裝結束後，讓首次更新完成，再正常結束 Nexon Launcher。若更新完成後沒有登入視窗，或視窗是空白／黑屏，在 CrossOver 選取剛建立的容器，使用「結束所有應用程式」關閉留在背景的 Nexon。接著直接進行下一步，登入視窗會由本專案的啟動工具開啟。
4. 使用上方連結下載 Apple Silicon 安裝包 `MabinogiMobileMac-arm64.zip` 並解壓縮，雙擊 **`install.command`**。依終端機提示完成一次 Mac 管理員驗證；輸入密碼時不會顯示字元。預先建置的安裝包不需要 Xcode。
5. 開啟 `~/Applications/瑪奇 Mobile 啟動.app`，明確選擇剛安裝台灣版 Nexon Launcher 的容器。若容器位於外接磁碟，請先掛載磁碟。macOS 首次詢問是否允許「瑪奇 Mobile 啟動」存取卸除式卷宗時，允許後才會顯示容器。若出現「設定 Nexon 登入回傳」，選擇「設定並繼續」。
6. 使用自己的 Nexon／Facebook 帳號登入。切回 Nexon 完成可能出現的電子郵件「帳戶驗證」，再安裝及執行遊戲。若瀏覽器詢問是否開啟「瑪奇 Mobile 啟動」，允許返回啟動器；目前台灣版 Facebook 流程也可能由 Nexon 在背景取回登入結果，不一定出現此提示。

之後直接開啟 **「瑪奇 Mobile 啟動」**。開機相容設定會自動套用。若希望保留登入狀態，完成 Facebook 登入後，請點 Nexon 右上角帳號選單 → **啟動器設定 → 一般 → 安全性 → 自動登入**，勾選後按「完成」。本次實測中，只有登入頁的「開啟自動登入功能」並未讓 Facebook 登入後的啟動器設定同步啟用，因此請在登入後確認這個選項。結束時使用帳號選單的「離開」，不要選「登出」或強制結束。未啟用或帳號工作階段到期時，仍需完成官方登入流程。

如果雙擊 `.command` 沒有執行，開啟終端機輸入 `/bin/bash `（尾端保留空白），將 `install.command` 拖進終端機，再按 Return。安裝包只有 ad-hoc 簽章，尚未取得 Developer ID 簽章或 Apple 公證；若 macOS 阻擋，請先確認檔案來自本儲存庫，再依系統提供的個別 App 開啟方式處理，無須停用整體安全保護。

安裝包在預設 Gatekeeper 設定下的提示尚未完成驗證。

### 先確認這些條件

- 這個版本針對**台灣版**，遊戲代號為 `59826`，不是韓版的通用啟動器。
- [官方配備頁](https://tw.nexon.com/mabinogimobile/home/support/download)列出的 PC 儲存空間為 **30 GB 以上**；安裝與更新時請額外預留空間。
- 實測容器使用圖形「自動」、關閉高解析度模式與 MSync。其他設定組合尚未逐一驗證。
- 啟動工具的編譯最低目標為 macOS 12；實際遊戲仍需符合所使用 CrossOver 版本的系統需求。
- 預先建置的安裝包適用於 **Apple Silicon（M 系列）**。**遊戲僅在上述 M1 環境實測**；Intel Mac 沒有預先建置版本，其他 macOS／CrossOver／遊戲版本及長時間遊玩尚未完成驗證。

## 修復內容

| 問題 | 處理方式 |
| --- | --- |
| Nexon 登入視窗黑屏、空白或未顯示 | 傳入 `--disable-blink-features=TextDecoratingBox`、`--disable-gpu` 與 `--in-process-gpu` |
| CrossOver 已安裝 Nexon，但啟動工具找不到外接磁碟上的容器 | 讀取 CrossOver 的容器資料夾設定，使用該資料夾和所選容器名稱啟動 Nexon |
| 遊戲下載完後，CrossOver 26.3 匯出捷徑時崩潰 | v0.1.3 將容器名稱與資料夾分開傳入 CrossOver，讓遊戲捷徑可對應到正確的容器 |
| 官網啟動或 Facebook 登入後無法返回 CrossOver | 以原生 App 接收 `nxl://`，交給選定容器中的官方 Nexon client |
| 下載一直卡在「驗證中」 | 依 ZeroMQ 的 Wine/macOS 建議，將 `net.inet.tcp.sendspace` 設為 `1300000` |
| 每次重開機都要重打指令 | 安裝一次執行即結束的系統 LaunchDaemon，開機時自動套用同一數值 |

TCP 設定會影響整台 Mac。本專案只安裝 `/Library/LaunchDaemons/io.github.kimi7011.mabinogi-mobile-macos.tcp.plist`，由 `root:wheel` 持有、權限 `0644`，直接呼叫系統 `sysctl`，不安裝常駐的特權執行檔。安裝前的數值保存在同一 plist，供移除時還原。

`nxl://` 是 Nexon 共用的 URL scheme。選擇此工具處理該類連結後，連結會送往所選的 CrossOver 容器；使用其他 Nexon 遊戲／容器時請留意處理程式的選擇。安裝器會記住原本的處理 App；移除時若仍由本工具處理連結，而且原 App 仍存在，便會還原。

### 保留現有入口、安裝另一份

安裝器會保留原修復入口，遇到同名舊 App 會停止並提示另選位置。可在下載包目錄執行：

```sh
bash install.command --app-dir "$HOME/Applications/MabinogiMobileMac"
```

往後開啟該子資料夾內的 App。第一次啟動不預選任何容器，明確選取後才會啟用「使用此容器」，避免誤開既有環境。同一個 macOS 帳號的公開版 App 共用容器選擇；請勿把同一容器當作隔離環境。

若管理員已用其他方式永久設定 TCP buffer，可加上 `--keep-network`。此選項只檢查目前數值至少為 `1000000`，不新增、移除或驗證其他開機項目；第一次安裝的一般使用者請勿使用。移除這種安裝時也須帶相同的 `--app-dir` 與 `--keep-network`，以保留既有網路設定。

## 移除與還原

先正常結束遊戲及 Nexon，再執行同一下載包中的 **`uninstall.command`**。

- 移除本專案的開機項目，並在目前數值仍是本專案設定時還原安裝前數值。如果其他管理員後來改過數值，保留後來的設定。
- 將本專案的啟動 App 移到垃圾桶。
- 保留 CrossOver 容器、遊戲、帳號資料及安裝時備份的舊入口。

舊入口備份位於 `~/Library/Application Support/MabinogiMobileMac/backups/`。本版移除工具只管理 `io.github.kimi7011.mabinogi-mobile-macos.tcp`；不會刪除其他專案或手動建立的開機設定。

## 從原始碼建置

原始碼不依賴第三方套件。需要 Apple Command Line Tools：

```sh
xcode-select --install
```

下載原始碼後，在專案目錄執行：

```sh
bash build.sh
python3 test.py "dist/瑪奇 Mobile 啟動.app"
bash install.command
```

`build.sh` 為目前 Mac 的架構建置 App，驗證 ad-hoc 簽章及 URL／參數自我測試。`test.py` 使用暫存資料夾與模擬的系統命令驗證安裝、重複安裝、還原、錯誤處理和防止覆寫無關檔案；不使用 sudo，也不變更實際系統設定。Intel Mac 可自行嘗試從原始碼建置，但本版未驗證其建置或遊戲相容性。

檢查目前環境，不啟動遊戲：

```sh
"dist/瑪奇 Mobile 啟動.app/Contents/MacOS/NexonBridge" --check
```

初版封裝已通過 Apple Silicon 編譯、腳本檢查與上述隔離測試。原修復的系統開機項目已在 2026-11-16 實際重新開機後執行成功，TCP 數值為 `1300000`；公開版開機項目已完成實際安裝／執行／移除，但尚未在保持安裝的情況下重開機驗證。編譯／隔離測試不等於在所有電腦完成遊戲實測。

同日續測發現，只有 `--disable-gpu` 仍可能沒有獨立 Nexon 視窗。以同一原容器對照啟動，增加 `--in-process-gpu` 後已直接觀察到完整的原生 Facebook 登入頁，並在關閉診斷功能後重測通過。使用者已確認原容器正常遊玩；公開包也已在隔離容器完成 Facebook／信箱驗證與遊戲啟動。

維護者進行隔離測試時，可對 App 執行檔傳入 `--keep-handler`，保留目前的 macOS `nxl://` 處理程式。此模式不會接管一般瀏覽器的 `nxl://` 回傳。此次台灣版 Facebook 流程由啟動器背景輪詢完成，已在保留原處理程式的情況下通過；其他需要 `nxl://` 回傳的登入方式須另以測試器明確送往指定 App。一般安裝不需要此選項。

## 常見問題

**找不到 Nexon Launcher**。請確認 CrossOver 設定的容器資料夾及外接磁碟可存取。如果先前拒絕外接磁碟存取，請到 macOS「系統設定 → 隱私權與安全性 → 檔案與檔案夾」檢查「瑪奇 Mobile 啟動」的卸除式卷宗權限，再重新開啟工具。錯誤視窗會顯示正在查找的容器資料夾。使用台灣官網提供的安裝器，讓它完成首次更新。本工具辨識安裝於 `C:\Program Files (x86)\Nexon\Nexon Launcher` 或 `C:\Program Files\Nexon\Nexon Launcher` 的 client。CrossOver 可透過「設定 → 系統整合」變更容器位置。 [CodeWeavers 說明](https://support.codeweavers.com/en_US/common-actions/change-the-bottle-directory-in-crossover-mac)

**剛安裝完 Nexon，卻沒有登入畫面**。先確認官方安裝和更新已完成。若 Nexon 還留在背景，請只對剛安裝 Nexon 的容器執行「結束所有應用程式」，再開啟「瑪奇 Mobile 啟動」。同一個 Nexon 程序若仍在執行，可能會沿用原本的啟動參數。如果正在玩遊戲，請先正常離開遊戲。

**遊戲已下載，但 CrossOver 26.3 出現 `exportProgram`／`updateApplicationFolder` 崩潰**。若曾用 v0.1.2 安裝，先更新至 v0.1.3 並關閉該容器先前啟動的 Nexon。若 CrossOver 仍反覆崩潰，可用 CrossOver 隨附的 `cxmenu` 重建該容器的捷徑，已下載的遊戲可繼續使用。請將 `Mabinogi Mobile` 換成實際容器名稱。如果 CrossOver 安裝在其他位置，請調整程式路徑。

```sh
bottle_folder="$(defaults read com.codeweavers.CrossOver BottleDir 2>/dev/null || true)"
if [ -z "$bottle_folder" ]; then
    bottle_folder="$HOME/Library/Application Support/CrossOver/Bottles"
fi
CX_BOTTLE_PATH="$bottle_folder" \
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/cxmenu" \
    --scope private --bottle "Mabinogi Mobile" --install
```

完成後重新開啟 CrossOver，從「瑪奇 Mobile 啟動」進入 Nexon，確認遊戲可繼續使用。

**需要重新選擇容器**：先結束 Nexon，再在終端機執行 `open -n "$HOME/Applications/瑪奇 Mobile 啟動.app" --args --choose-bottle`。若裝在其他資料夾，請替換 App 路徑。新的選擇也適用於後續登入回傳。

**仍卡在驗證**：執行 `sysctl net.inet.tcp.sendspace`，確認至少為 `1000000`；本專案使用 `1300000`。再檢查 `launchctl print system/io.github.kimi7011.mabinogi-mobile-macos.tcp`。正常的一次性工作會顯示已結束與 `last exit code = 0`，不需要一直執行中。

**Facebook 顯示「返回遊戲啟動器」，卻沒有進入遊戲**：先切回獨立的 Nexon 視窗。Facebook 成功頁只代表第三方驗證已完成；新容器可能還要完成 Nexon 的電子郵件「帳戶驗證」。完成後才會進入遊戲頁，首次使用仍需安裝遊戲並按「開始遊戲」。不要反覆重新整理或重開舊的登入完成網址。

**每次重開仍要求 Facebook 登入**：完成一次登入後，在「啟動器設定 → 一般 → 安全性」確認「自動登入」已勾選。登入頁的勾選狀態不能代替這項確認。這會在該容器保留登入狀態；共用電腦請依自己的需要選擇。

點擊啟動後請先等候約 30 秒；本機實測約 13 秒才建立遊戲程序，速度會因電腦與遊戲更新而異。若 Nexon 已顯示遊戲頁的「執行」按鈕，可直接按該按鈕繼續。

若 Nexon 仍停在「請從瀏覽器登入」或等待逾時，按「取消」，從同一個 Nexon 視窗重新按 Facebook，使用這次新開啟的官方登入頁。若 Nexon 只剩頁尾或空白，先正常結束這個 Nexon，再開啟「瑪奇 Mobile 啟動」重新登入。不要在遊戲執行時重啟容器，也不要結束其他容器的程式。本工具不會保存驗證碼、繞過帳戶驗證或無限制重送登入。

**更新 Nexon 後不能啟動**：先在原容器執行官方 `nexon_launcher.exe` 完成更新，再使用本工具。新版啟動器可能改變目錄結構或不再需要相同參數，請附上版本及錯誤訊息回報。

回報問題時請提供機型、macOS／CrossOver／Nexon 版本、卡住的步驟及已遮蔽帳號的畫面。不要上傳完整登入網址、token、cookies 或原始帳號日誌。

## 授權與來源

本專案自行撰寫的啟動工具與腳本採用 [MIT 授權](LICENSE)。不封裝 CrossOver、Nexon、遊戲、反作弊程式或任何玩家資料；不修補 `app.asar`、遊戲執行檔或反作弊元件。商標與遊戲內容屬原權利人。

技術參考：

- [ZeroMQ 官方 INSTALL：Windows Builds – Wine](https://github.com/zeromq/libzmq/blob/master/INSTALL)：TCP buffer 的相容建議。
- [linux-launcher 開發者的疑難排解紀錄](https://github.com/xthddrt/linux-launcher/blob/main/docs/TROUBLESHOOTING.md)：Electron 文字繪製相容參數的參考；未封裝該專案的程式或補丁。
- [Apple：Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)：開機服務機制。
- [瑪奇 Mobile 台灣官方下載與配備](https://tw.nexon.com/mabinogimobile/home/support/download)。

English: A community macOS/CrossOver launcher helper for the Taiwan edition of Mabinogi Mobile. It handles Nexon URL callbacks, applies Electron compatibility flags, and installs a reversible startup TCP-buffer setting. CrossOver and the official Nexon/game installation are required. Tested gameplay startup is limited to the M1 configuration above; no game binaries or account data are distributed.
