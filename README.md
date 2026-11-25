# 瑪奇 Mobile × macOS

用 CrossOver 在 Apple Silicon Mac 啟動台灣版《瑪奇 Mobile》。v0.1.6 每次安裝或更新時，會從台灣 App Store 取得 NEXON 最新上架的遊戲圖示。舊版啟動器會封存為 ZIP，避免新舊版本同時執行而反覆跳出外接磁碟權限提示。

**[下載 v0.1.6 安裝包](https://github.com/kimi7011/mabinogi-mobile-macos/raw/refs/heads/main/MabinogiMobileMac-arm64.zip)** · [SHA-256](https://github.com/kimi7011/mabinogi-mobile-macos/blob/main/SHA256SUMS.txt) · [回報問題](https://github.com/kimi7011/mabinogi-mobile-macos/issues)

啟動時會自動為瑪奇容器套用 DXMT，需使用 Apple Silicon、macOS 14 以上，以及含 DXMT 的 CrossOver。

## 已經安裝，怎麼更新

1. 正常結束遊戲，從 Nexon 右上角帳號選單點「離開」，並在 CrossOver 結束該容器中仍在背景執行的程式。
2. 解壓新版安裝包，雙擊 `install.command`，依提示完成安裝。
3. 開啟「瑪奇 Mobile 啟動」。新版會沿用原本選定的容器。Nexon 已啟用自動登入時，也會沿用既有登入狀態。

## 第一次安裝

1. 在 CrossOver 建立瑪奇專用的 **Windows 10 64 位元**容器，安裝台灣版 Nexon Launcher。等它完成更新後再離開。[下載台灣版 Nexon Launcher](https://download.nxfs.nexon.com/download-launcher?file=NexonLauncherSetup_TW.exe&product-id=59826)
2. 解壓本專案的安裝包，雙擊 `install.command`，依提示完成一次 Mac 管理員驗證。
3. 開啟「瑪奇 Mobile 啟動」，選擇剛建立的容器，完成 Nexon 登入、下載及啟動遊戲。

## 本機實測

2026-11-16 20:50（台灣時間）驗證。Apple M6、16 GB、macOS 27.0.1、CrossOver 26.3、瑪奇啟動器 **v0.1.4**。

沿用原容器與 Nexon 登入重新開啟。新版自動補回先移除的 DXMT 設定，遊戲已啟動並實際載入 DXMT。

2026-11-25 另確認外接磁碟權限連跳是同一個 App 識別碼的新舊副本同時執行。封存舊副本與清理殘留程序後重新開啟，Nexon Launcher 成功啟動，系統未再重複提示。v0.1.5 通過 ZIP 備份、舊備份轉換與安裝失敗還原測試。

## 其他說明

移除啟動器請執行 `uninstall.command`。切換容器、安裝問題和建置方式請看[進階說明](docs/advanced.md)。

本工具為社群專案。啟動器與腳本採用 [MIT 授權](LICENSE)。
