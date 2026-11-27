cask "mabinogi-mobile-macos" do
  version "0.1.10"
  sha256 "fc13fc022cc9614b4517312285b8b7455074a1f4c4cd3161e1e14545f189cab1"

  url "https://github.com/kimi7011/mabinogi-mobile-macos/releases/download/v#{version}/MabinogiMobileMac-arm64.zip"
  name "瑪奇 Mobile 啟動"
  desc "CrossOver launcher for the Taiwan edition of Mabinogi Mobile"
  homepage "https://github.com/kimi7011/mabinogi-mobile-macos"

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "MabinogiMobileMac-arm64/Support/瑪奇 Mobile 啟動.app"
  binary "MabinogiMobileMac-arm64/Support/network-settings.sh", target: "mabinogi-mobile-network"

  preflight_steps do
    run "/bin/bash",
        args:           ["{{staged_path}}/MabinogiMobileMac-arm64/安裝並啟動.command",
                         "--cask-stage", "{{staged_path}}/MabinogiMobileMac-arm64/Support",
                         "--app-dir", "{{appdir}}"],
        network_access: true,
        print_stdout:   true
  end

  caveats <<~EOS
    初次使用時，請在終端機完成一次網路相容設定：
      sudo "$(command -v mabinogi-mobile-network)" install

    請先在 CrossOver 安裝台版 Nexon Launcher，再開啟「瑪奇 Mobile 啟動」。
    https://github.com/kimi7011/mabinogi-mobile-macos#第一次安裝
  EOS
end
