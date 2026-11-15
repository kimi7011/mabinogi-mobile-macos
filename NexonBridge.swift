import AppKit

// Taiwan edition. Authentication URLs are passed as one argument and never logged.
enum Launcher {
    static let gameURL = "nxl://play/59826"
    static let downloadURL = URL(string: "https://tw.nexon.com/mabinogimobile/home/support/download")!
    static let flags = ["--disable-blink-features=TextDecoratingBox", "--disable-gpu"]
    static let bottles = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CrossOver/Bottles")

    static func validURL(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32_768 &&
        !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) &&
        URL(string: value)?.scheme?.lowercased() == "nxl"
    }

    static func validBottle(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.hasPrefix("-") &&
        !name.contains("/") && !name.contains("\\") &&
        !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }

    static func wineURL() -> URL? {
        let fm = FileManager.default
        let candidates = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.codeweavers.CrossOver"),
                          URL(fileURLWithPath: "/Applications/CrossOver.app"),
                          fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app")]
        return candidates.compactMap { $0?.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine") }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }

    static func clientDirectory(_ bottle: String) -> URL? {
        guard validBottle(bottle) else { return nil }
        for programFiles in ["Program Files (x86)", "Program Files"] {
            let directory = bottles.appendingPathComponent(bottle)
                .appendingPathComponent("drive_c/\(programFiles)/Nexon/Nexon Launcher/bin/nexon_client")
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("nexon_client.exe").path) {
                return directory
            }
        }
        return nil
    }

    static func availableBottles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bottles.path)) ?? [])
            .filter { clientDirectory($0) != nil }.sorted()
    }

    static func arguments(bottle: String, directory: URL, url: String) -> [String] {
        let programFiles = directory.path.contains("/Program Files (x86)/") ? "Program Files (x86)" : "Program Files"
        return ["--bottle", bottle, "--no-wait", "--debugmsg", "-all", "--workdir", directory.path,
                directory.appendingPathComponent("nexon_client.exe").path] + flags +
               ["--nxl=" + url, "C:\\\(programFiles)\\Nexon\\Nexon Launcher\\bin\\front_end"]
    }

    static func tcpBuffer() -> Int? {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        task.arguments = ["-n", "net.inet.tcp.sendspace"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            return Int(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch { return nil }
    }
}

final class NexonBridge: NSObject, NSApplicationDelegate {
    private var receivedURL = false
    private var jobs: [UUID: Process] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.receivedURL else { return }
            self.launch(Launcher.gameURL)
        }
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        receivedURL = true
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              Launcher.validURL(value) else {
            fail("無法開啟此連結", "請從瑪奇 Mobile 台灣官方網站重新啟動或登入。")
            return
        }
        launch(value)
    }

    private func fail(_ title: String, _ message: String, download: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if download { alert.addButton(withTitle: "開啟官方下載頁") }
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Launcher.downloadURL) }
        NSApp.terminate(nil)
    }

    private func selectedBottle() -> String? {
        let names = Launcher.availableBottles()
        if let saved = UserDefaults.standard.string(forKey: "BottleName"), names.contains(saved) { return saved }
        if names.contains("Mabinogi Mobile") { return "Mabinogi Mobile" }
        guard !names.isEmpty else { return nil }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        picker.addItems(withTitles: names)
        let alert = NSAlert()
        alert.messageText = "選擇 Nexon Launcher 所在的 CrossOver 容器"
        alert.informativeText = "請選擇已安裝台灣版 Nexon Launcher 的容器。"
        alert.accessoryView = picker
        alert.addButton(withTitle: "使用此容器")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, let name = picker.titleOfSelectedItem else { return nil }
        UserDefaults.standard.set(name, forKey: "BottleName")
        return name
    }

    private func launch(_ url: String) {
        guard let wine = Launcher.wineURL() else {
            fail("找不到 CrossOver", "請先安裝並啟用 CodeWeavers CrossOver，再開啟這個啟動工具。")
            return
        }
        guard (Launcher.tcpBuffer() ?? 0) >= 1_000_000 else {
            fail("需要安裝網路相容設定", "請執行下載包中的 install.command，完成一次管理員驗證。之後開機會自動套用，避免 Nexon 一直停在驗證中。")
            return
        }
        guard !Launcher.availableBottles().isEmpty else {
            fail("尚未選定 Nexon Launcher", "請先在 CrossOver 的 Windows 10 64 位元容器安裝台灣官方 Nexon Launcher。建議容器名稱為 Mabinogi Mobile。", download: true)
            return
        }
        guard let bottle = selectedBottle(), let directory = Launcher.clientDirectory(bottle) else {
            NSApp.terminate(nil)
            return
        }
        let id = UUID(), task = Process()
        task.executableURL = wine
        task.arguments = Launcher.arguments(bottle: bottle, directory: directory, url: url)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.jobs.removeValue(forKey: id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if self?.jobs.isEmpty == true { NSApp.terminate(nil) }
                }
            }
        }
        do {
            jobs[id] = task
            try task.run()
        } catch {
            jobs.removeValue(forKey: id)
            fail("無法啟動 Nexon", "請確認 CrossOver 與選定容器內的 Nexon Launcher 仍在原本的位置。")
        }
    }
}

// A local test path: it does not open Nexon, change settings, or handle real credentials.
if CommandLine.arguments.contains("--self-test") {
    let invalid = ["", "https://example.com", "nxl://play/1\n", "nxl://play/1\t", "nxl://play/1\u{7f}", "nxl:" + String(repeating: "a", count: 32_768)]
    precondition(invalid.allSatisfy { !Launcher.validURL($0) })
    precondition(Launcher.validURL(Launcher.gameURL))
    precondition(Launcher.validURL("NXL://example?value=a%20b"))
    precondition(["..", "-x", "a/b", "a\\b", "a\n"].allSatisfy { !Launcher.validBottle($0) })
    let sample = "nxl://example?value=$(touch%20SHOULD_NOT_EXIST)&quote='test'"
    let directory = URL(fileURLWithPath: "/example/Program Files (x86)/Nexon/Nexon Launcher/bin/nexon_client")
    let args = Launcher.arguments(bottle: "Bottle with spaces", directory: directory, url: sample)
    precondition(args.contains("--nxl=" + sample))
    precondition(args[1] == "Bottle with spaces")
    precondition(args.last == "C:\\Program Files (x86)\\Nexon\\Nexon Launcher\\bin\\front_end")
    precondition(!args.contains("--no-sandbox"))
    print("PASS: URL validation, bottle validation, argument boundaries, compatibility flags")
    exit(0)
}
if CommandLine.arguments.contains("--check") {
    print("CrossOver found: \(Launcher.wineURL() != nil)")
    print("Nexon bottle found: \(!Launcher.availableBottles().isEmpty)")
    print("TCP buffer sufficient: \((Launcher.tcpBuffer() ?? 0) >= 1_000_000)")
    exit(0)
}
let delegate = NexonBridge()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
