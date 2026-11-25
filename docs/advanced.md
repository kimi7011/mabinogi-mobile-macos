# 疑難排解與維護

首次安裝請看 [專案首頁](../README.md)。

## 安裝或開啟失敗

- **macOS 擋下首次開啟**。若已確認來源與檔案完整性，先嘗試打開檔案，再到「系統設定 → 隱私權與安全性」使用針對該檔案的「強制打開」選項。[Apple 支援](https://support.apple.com/zh-tw/102445)
- **找不到已安裝的 App**。在 Finder 選「前往 → 前往檔案夾」，輸入 `~/Applications`，開啟「瑪奇 Mobile 啟動」。
- **找不到容器**。請先在 CrossOver 給台灣版 Nexon Launcher 建立專用的 Windows 10 64 位元容器。容器放在外接磁碟時，先掛載磁碟，並依 macOS 提示允許存取卸除式卷宗。
- **找不到圖示或圖示下載失敗**。安裝器會在安裝或更新時從台灣 App Store 下載最新官方圖示。若來源查詢或下載失敗，請確認網路後重試。[台灣 App Store](https://apps.apple.com/tw/app/id6759030432)

## 登入、更新與圖形

- 首次開啟可能會詢問是否由此 App 處理 Nexon 登入連結。若 Nexon 或 Facebook 要求額外驗證，切回原本的 Nexon 視窗完成。
- 遊戲更新卡住時，在原容器中完全關閉遊戲與 Nexon Launcher，再從官方 Nexon Launcher 完成更新。
- 此工具會在相容的 Apple 晶片 Mac 和 CrossOver 上，為選定的瑪奇容器套用 DXMT。請使用專用容器，因為容器內其他 Windows 程式也會使用該圖形設定。[CodeWeavers 圖形設定](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac-26)
- 要重新選擇容器，先關閉遊戲與 Nexon，再執行 `open -n "$HOME/Applications/瑪奇 Mobile 啟動.app" --args --choose-bottle`。

## 移除、備份與管理

- 解壓縮的安裝包內，`Support/uninstall.command` 可以移除工具並還原它安裝的網路相容設定。CrossOver 容器和遊戲檔案會保留。
- 安裝器會設定全機的 TCP 傳送緩衝區，處理某些 CrossOver 環境的 Nexon 下載驗證問題。這項設定會在重開機後套用，需要 Mac 管理員驗證。密碼輸入時終端機不會顯示字元。[Wine 網路說明](https://github.com/zeromq/libzmq/blob/master/INSTALL)
- 更新前的舊啟動器會封存成 ZIP，位於 `~/Library/Application Support/MabinogiMobileMac/backups/`。若要回復，先關閉容器內的程式，再用解壓縮出的舊 App **取代**目前的 App。每次使用同一個安裝入口。
- 命令列可用 `--no-launch` 只安裝。若已自行維護 TCP 緩衝區，可使用 `--keep-network`。安裝、移除都應使用相同的網路選項及 App 位置。

## 開發

在裝有 Apple Command Line Tools 的 Mac 上執行：

```sh
bash build.sh
python3 test.py 'dist/瑪奇 Mobile 啟動.app'
```

本機建置可設定 `MABINOGI_ICON_PATH` 指定 `.icns` 圖示。回報問題時請附 macOS 和 CrossOver 版本，以及出錯的步驟。請遮蔽帳號和登入資訊。
