# 瑪奇 Mobile 台服 Mac 啟動器

用 CrossOver 在 Apple 晶片 Mac 玩台服。完成首次設定後，點「瑪奇 Mobile 啟動」就能開遊戲。

**[下載最新版安裝包](https://github.com/kimi7011/mabinogi-mobile-macos/releases/latest/download/MabinogiMobileMac-arm64.zip)**

## 第一次安裝

1. [下載並開啟 CrossOver](https://www.codeweavers.com/crossover/download-links)，選擇試用或啟用授權。建議使用 macOS 14 或更新版本。
2. [下載台灣版 Nexon Launcher](https://download.nxfs.nexon.com/download-launcher?file=NexonLauncherSetup_TW.exe)。在 CrossOver 選「安裝 → 安裝未列出的應用程式」，選取安裝檔，建立專用的 **Windows 10 64 位元容器**。等 Nexon Launcher 完成首次更新後關閉它，再做下一步。若更新完成後視窗仍是透明的，參考[關閉透明視窗的步驟](docs/advanced.md#nexon-launcher-開啟後是透明視窗)。[CrossOver 圖文指南](https://support.codeweavers.com/getting-started/installing-an-unlisted-application)
3. 解壓縮本工具的 ZIP，連按兩下 **「安裝並啟動.command」**。安裝時需要網路，並透過管理員驗證套用網路相容設定。第一次開啟後，依畫面選擇容器、登入 Nexon 並下載遊戲。

之後直接開啟個人「應用程式」資料夾（`~/Applications`）裡的 **「瑪奇 Mobile 啟動」**。Nexon 若要求重新登入或下載更新，依它的畫面完成即可。

## 更新或排除問題

更新啟動器時，先關閉遊戲及 CrossOver 容器內的 Nexon Launcher，再執行新版的「安裝並啟動.command」。安裝會沿用原本的容器和 Nexon 登入設定。

[macOS 開啟提示、移除與疑難排解](docs/advanced.md) · [SHA-256](https://github.com/kimi7011/mabinogi-mobile-macos/releases/latest/download/SHA256SUMS.txt) · [回報問題](https://github.com/kimi7011/mabinogi-mobile-macos/issues)

## 用 Homebrew 安裝

若已使用 Homebrew，可以用下面的指令取代第一次安裝的第 3 步。

```sh
brew tap kimi7011/mabinogi-mobile-macos https://github.com/kimi7011/mabinogi-mobile-macos.git
brew install --cask --appdir="$HOME/Applications" kimi7011/mabinogi-mobile-macos/mabinogi-mobile-macos
```

第一次使用時，在同一個終端機執行 `sudo "$(command -v mabinogi-mobile-network)" install`，完成一次網路相容設定。接著從個人的「應用程式」資料夾開啟「瑪奇 Mobile 啟動」。[接手 ZIP 版、升級與移除](docs/advanced.md#homebrew-維護)。

社群製作的啟動工具，採用 [MIT 授權](LICENSE)。
