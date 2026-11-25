import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum AppIcon {
    enum RenderError: LocalizedError {
        case invalidArtwork
        case cannotRender

        var errorDescription: String? {
            switch self {
            case .invalidArtwork: return "圖示來源必須是邊長 512 至 2048 像素且大小未超過 4 MiB 的正方形 PNG。"
            case .cannotRender: return "無法產生 macOS 圖示。"
            }
        }
    }

    static func makeIconset(from input: URL, at output: URL) throws {
        let maximumSize = 4 * 1024 * 1024
        let metadata = try input.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard metadata.isRegularFile == true, let fileSize = metadata.fileSize,
              (1...maximumSize).contains(fileSize),
              let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetType(source) == UTType.png.identifier as CFString,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              (512...2048).contains(width),
              properties[kCGImagePropertyPixelHeight] as? Int == width,
              let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RenderError.invalidArtwork
        }

        let files = FileManager.default
        try files.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            for size in [16, 32, 128, 256, 512] {
                try render(artwork, side: size, to: output.appendingPathComponent("icon_\(size)x\(size).png"))
                try render(artwork, side: size * 2, to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
            }
        } catch {
            try? files.removeItem(at: output)
            throw error
        }
    }

    private static func render(_ artwork: CGImage, side: Int, to file: URL) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.cannotRender
        }
        let extent = CGFloat(side) * 0.8046875
        let inset = (CGFloat(side) - extent) / 2
        let box = CGRect(x: inset, y: inset, width: extent, height: extent)
        let radius = extent * 0.21
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(artwork, in: box)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.cannotRender
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.cannotRender }
    }
}

struct NexonBottle {
    let directory: URL
    let programFiles: String

    var name: String { directory.lastPathComponent }
    var root: URL { directory.deletingLastPathComponent() }
    var clientDirectory: URL {
        directory.appendingPathComponent("drive_c/\(programFiles)/Nexon/Nexon Launcher/bin/nexon_client")
    }
    var executable: URL { clientDirectory.appendingPathComponent("nexon_client.exe") }
}

enum BottleGraphics {
    private static let sectionHeader = try! NSRegularExpression(pattern: #"^\[(.*)\][ \t]*(?:;[^\]]*)?$"#)
    private static let backendSetting = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:"CX_GRAPHICS_BACKEND"|CX_GRAPHICS_BACKEND)[ \t]*=[ \t]*(?:"(?:[^"\\]|\\.)*"([ \t]*;.*)?[ \t]*|.*)$"#,
        options: .caseInsensitive
    )
    private static let dxmtSetting = #""CX_GRAPHICS_BACKEND" = "dxmt""#

    static func supportsDXMT(wine: URL) -> Bool {
#if arch(arm64)
        guard #available(macOS 14, *) else { return false }
        let root = wine.deletingLastPathComponent().deletingLastPathComponent()
        return ["lib", "lib64"].contains { path in
            let dxmt = root.appendingPathComponent("\(path)/dxmt", isDirectory: true)
            return ["x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "x86_64-unix/winemetal.so"].allSatisfy {
                FileManager.default.isReadableFile(atPath: dxmt.appendingPathComponent($0).path)
            }
        }
#else
        return false
#endif
    }

    static func configurationSelectingDXMT(_ source: String) -> String {
        var inEnvironment = false
        var environmentEnd: String.Index?
        var foundBackend = false
        var edits: [(range: NSRange, value: String)] = []
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byLines) { text, range, lineRange, _ in
            guard let text else { return }
            let line = text.trimmingCharacters(in: .whitespaces)
            if let header = sectionHeader.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                inEnvironment = (line as NSString).substring(with: header.range(at: 1)).lowercased() == "environmentvariables"
            }
            guard inEnvironment else { return }
            environmentEnd = lineRange.upperBound
            guard let entry = backendSetting.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return }
            foundBackend = true
            let original = text as NSString
            let comment = entry.range(at: 2)
            let value = original.substring(with: entry.range(at: 1)) + dxmtSetting +
                (comment.location == NSNotFound ? "" : original.substring(with: comment))
            if value != text { edits.append((NSRange(range, in: source), value)) }
        }

        if foundBackend {
            guard !edits.isEmpty else { return source }
            let updated = NSMutableString(string: source)
            for edit in edits.reversed() { updated.replaceCharacters(in: edit.range, with: edit.value) }
            return updated as String
        }

        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        let insertion = environmentEnd ?? source.endIndex
        let before = source[..<insertion]
        let separator = before.isEmpty || before.utf8.last == 10 ? "" : newline
        let header = environmentEnd == nil ? "[EnvironmentVariables]" + newline : ""
        return before + separator + header + dxmtSetting + newline + source[insertion...]
    }

    static func applyDXMT(to bottle: NexonBottle) throws {
        let file = bottle.directory.appendingPathComponent("cxbottle.conf")
        let resource = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard resource.isRegularFile == true, resource.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        // Re-read if CrossOver saved changes while we were preparing the update.
        for _ in 0..<2 {
            let original = try Data(contentsOf: file)
            guard let source = String(data: original, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            let updated = Data(configurationSelectingDXMT(source).utf8)
            guard updated != original else { return }
            guard FileManager.default.isWritableFile(atPath: file.path) else { throw CocoaError(.fileWriteNoPermission) }
            guard try Data(contentsOf: file) == original else { continue }
            try updated.write(to: file, options: .atomic)
            return
        }
        throw CocoaError(.fileWriteUnknown)
    }
}

// Taiwan edition. Authentication URLs are passed as one argument and never logged.
enum Launcher {
    static let gameURL = "nxl://play/59826"
    static let downloadURL = URL(string: "https://tw.nexon.com/mabinogimobile/home/support/download")!
    static let flags = ["--disable-blink-features=TextDecoratingBox", "--disable-gpu", "--in-process-gpu"]
    static let crossOverID = "com.codeweavers.CrossOver"
    static let defaultBottles = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)

    static func bottleRoot(configuredPath: String?) -> URL {
        guard let path = configuredPath, path.hasPrefix("/") else { return defaultBottles }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func configuredBottleRoot() -> URL {
        let path = CFPreferencesCopyAppValue("BottleDir" as CFString, crossOverID as CFString) as? String
        return bottleRoot(configuredPath: path)
    }

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
        let candidates = [NSWorkspace.shared.urlForApplication(withBundleIdentifier: crossOverID),
                          URL(fileURLWithPath: "/Applications/CrossOver.app"),
                          fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app")]
        return candidates.compactMap { $0?.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine") }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }

    static func nexonBottle(named name: String, in root: URL) -> NexonBottle? {
        guard validBottle(name) else { return nil }
        let directory = root.appendingPathComponent(name, isDirectory: true)
        for programFiles in ["Program Files (x86)", "Program Files"] {
            let bottle = NexonBottle(directory: directory, programFiles: programFiles)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: bottle.executable.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return bottle
            }
        }
        return nil
    }

    static func availableBottles(in root: URL) -> [NexonBottle] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .sorted().compactMap { nexonBottle(named: $0, in: root) }
    }

    static func arguments(bottle: NexonBottle, url: String) -> [String] {
        // CrossOver uses the bottle name again when exporting macOS shortcuts.
        return ["--bottle", bottle.name, "--scope", "private", "--no-wait", "--debugmsg", "-all", "--workdir",
                bottle.clientDirectory.path, bottle.executable.path] + flags +
               ["--nxl=" + url, "C:\\\(bottle.programFiles)\\Nexon\\Nexon Launcher\\bin\\front_end"]
    }

    static func configureGraphics(wine: URL, bottle: NexonBottle, url: String) throws {
        guard let link = URL(string: url), link.scheme?.lowercased() == "nxl",
              link.host?.lowercased() == "play", link.path == "/59826",
              BottleGraphics.supportsDXMT(wine: wine) else { return }
        try BottleGraphics.applyDXMT(to: bottle)
    }

    static func environment(bottle: NexonBottle, inherited: [String: String]) -> [String: String] {
        var environment = inherited
        environment["CX_BOTTLE_PATH"] = bottle.root.path
        environment.removeValue(forKey: "CX_INITIALIZED")
        return environment
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
    private weak var bottlePickerButton: NSButton?

    @objc private func bottleSelectionChanged(_ sender: NSPopUpButton) {
        bottlePickerButton?.isEnabled = sender.indexOfSelectedItem > 0
    }

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

    private func selectedBottle(from bottles: [NexonBottle]) -> NexonBottle? {
        let defaults = UserDefaults.standard
        if !CommandLine.arguments.contains("--choose-bottle") {
            let savedPath = defaults.string(forKey: "BottlePath")
            if let saved = bottles.first(where: { $0.directory.path == savedPath }) { return saved }
            // Previous versions only searched the default root.
            if savedPath == nil, let name = defaults.string(forKey: "BottleName"),
               let saved = bottles.first(where: {
                   $0.name == name && $0.directory.deletingLastPathComponent().path == Launcher.defaultBottles.path
               }) {
                defaults.set(saved.directory.path, forKey: "BottlePath")
                return saved
            }
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        picker.addItems(withTitles: ["請選擇容器…"] + bottles.map(\.name))
        picker.menu?.items.first?.isEnabled = false
        picker.target = self
        picker.action = #selector(bottleSelectionChanged(_:))
        let alert = NSAlert()
        alert.messageText = "選擇 Nexon Launcher 所在的 CrossOver 容器"
        alert.informativeText = "請選擇用於瑪奇 Mobile、已安裝台灣版 Nexon Launcher 的容器。往後的啟動、圖形設定與登入回傳都會使用此容器。"
        alert.accessoryView = picker
        let useButton = alert.addButton(withTitle: "使用此容器")
        useButton.isEnabled = false
        bottlePickerButton = useButton
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        defer { bottlePickerButton = nil }
        guard alert.runModal() == .alertFirstButtonReturn,
              let name = picker.titleOfSelectedItem,
              let bottle = bottles.first(where: { $0.name == name }) else { return nil }
        defaults.set(bottle.directory.path, forKey: "BottlePath")
        return bottle
    }

    private func prepareHandler(_ completion: @escaping () -> Void) {
        // An isolated integration harness can deliver the URL to this App
        // explicitly, without replacing another installed Nexon handler.
        if CommandLine.arguments.contains("--keep-handler") {
            completion()
            return
        }
        let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: Launcher.gameURL)!)
        // Gatekeeper may run a downloaded App from an AppTranslocation path.
        // All copies of this tool share the selected bottle in UserDefaults, so
        // an installed handler with our bundle ID already routes to that bottle.
        let ownID = Bundle.main.bundleIdentifier
        let handledByThisTool = ownID != nil && current.flatMap { Bundle(url: $0)?.bundleIdentifier } == ownID
        if current?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL || handledByThisTool {
            completion()
            return
        }
        let alert = NSAlert()
        alert.messageText = "設定 Nexon 登入回傳"
        alert.informativeText = "將 nxl:// 連結交給此工具，讓 Facebook／Nexon 登入後回到剛才選定的容器。這也會影響其他 Nexon 遊戲的啟動連結；移除工具時可還原原本的處理程式。"
        alert.addButton(withTitle: "設定並繼續")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "nxl") { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.fail("無法設定登入回傳", "macOS 未允許此工具接收 Nexon 連結。請重新開啟工具，再依系統提示選擇處理程式。")
                    return
                }
                if let current, UserDefaults.standard.string(forKey: "PreviousNXLHandlerPath") == nil {
                    UserDefaults.standard.set(current.path, forKey: "PreviousNXLHandlerPath")
                }
                completion()
            }
        }
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
        let root = Launcher.configuredBottleRoot()
        guard !root.path.contains(":") else {
            fail("CrossOver 容器資料夾的路徑含有冒號", "CrossOver 的命令列會把冒號視為資料夾分隔符號。請在 CrossOver 的「系統整合」設定中選擇路徑沒有冒號的容器資料夾。")
            return
        }
        let bottles = Launcher.availableBottles(in: root)
        guard !bottles.isEmpty else {
            fail("找不到已安裝的 Nexon Launcher", "請確認 CrossOver 的容器資料夾可存取，並在 Windows 10 64 位元容器完成台灣版 Nexon Launcher 安裝。\n\n容器資料夾\n\(root.path)", download: true)
            return
        }
        guard let bottle = selectedBottle(from: bottles) else {
            NSApp.terminate(nil)
            return
        }
        prepareHandler { self.runClient(wine: wine, bottle: bottle, url: url) }
    }

    private func runClient(wine: URL, bottle: NexonBottle, url: String) {
        do {
            try Launcher.configureGraphics(wine: wine, bottle: bottle, url: url)
        } catch {
            fail("無法自動套用 DXMT", "請確認容器「\(bottle.name)」的 cxbottle.conf 可寫入，再重新開啟。若選錯容器，請用 --choose-bottle 重新選擇。\n\n\(error.localizedDescription)")
            return
        }
        let id = UUID(), task = Process()
        task.executableURL = wine
        task.arguments = Launcher.arguments(bottle: bottle, url: url)
        task.environment = Launcher.environment(bottle: bottle, inherited: ProcessInfo.processInfo.environment)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] finishedTask in
            let status = finishedTask.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.jobs.removeValue(forKey: id)
                if status != 0, self.jobs.isEmpty {
                    self.fail("CrossOver 無法啟動 Nexon", "請確認容器「\(bottle.name)」和容器所在的磁碟仍可存取，再重新開啟。\n\nCrossOver 結束代碼 \(status)")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if self.jobs.isEmpty { NSApp.terminate(nil) }
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

if CommandLine.arguments.dropFirst().first == "--make-app-icon" {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else {
        fputs("用法：--make-app-icon INPUT.png OUTPUT.iconset\n", stderr)
        exit(2)
    }
    do {
        try AppIcon.makeIconset(from: URL(fileURLWithPath: arguments[2]),
                               at: URL(fileURLWithPath: arguments[3], isDirectory: true))
        exit(0)
    } catch {
        fputs("無法製作啟動器圖示。\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Remember before LaunchServices sees the new App, since registration alone may
// select it when the previous handler was only an implicit system choice.
if CommandLine.arguments.contains("--remember-handler") {
    if UserDefaults.standard.string(forKey: "PreviousNXLHandlerPath") == nil,
       let previous = NSWorkspace.shared.urlForApplication(toOpen: URL(string: Launcher.gameURL)!),
       Bundle(url: previous)?.bundleIdentifier != Bundle.main.bundleIdentifier {
        UserDefaults.standard.set(previous.path, forKey: "PreviousNXLHandlerPath")
    }
    exit(0)
}
if CommandLine.arguments.contains("--restore-handler") {
    let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: Launcher.gameURL)!)
    if let current, Bundle(url: current)?.bundleIdentifier == Bundle.main.bundleIdentifier,
       let previous = UserDefaults.standard.string(forKey: "PreviousNXLHandlerPath"),
       FileManager.default.fileExists(atPath: previous) {
        var finished = false
        var failed = false
        NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: previous), toOpenURLsWithScheme: "nxl") { error in
            DispatchQueue.main.async { failed = error != nil; finished = true }
        }
        while !finished { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
        guard !failed else { fputs("無法還原登入處理程式，已保留 App。\n", stderr); exit(1) }
        UserDefaults.standard.removeObject(forKey: "PreviousNXLHandlerPath")
        print("已還原原本的 Nexon 連結處理程式。")
    }
    exit(0)
}

// A local test path that only modifies temporary fixtures.
if CommandLine.arguments.contains("--self-test") {
    let invalid = ["", "https://example.com", "nxl://play/1\n", "nxl://play/1\t", "nxl://play/1\u{7f}", "nxl:" + String(repeating: "a", count: 32_768)]
    precondition(invalid.allSatisfy { !Launcher.validURL($0) })
    precondition(Launcher.validURL(Launcher.gameURL))
    precondition(Launcher.validURL("NXL://example?value=a%20b"))
    precondition(["..", "-x", "a/b", "a\\b", "a\n"].allSatisfy { !Launcher.validBottle($0) })
    let sample = "nxl://example?value=$(touch%20SHOULD_NOT_EXIST)&quote='test'"
    precondition(Launcher.bottleRoot(configuredPath: nil) == Launcher.defaultBottles)
    precondition(Launcher.bottleRoot(configuredPath: "relative/path") == Launcher.defaultBottles)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = Launcher.bottleRoot(configuredPath: temporary.appendingPathComponent("External SSD/Bottles").path)
        let bottle = NexonBottle(directory: root.appendingPathComponent("容器 with spaces"), programFiles: "Program Files (x86)")
        try FileManager.default.createDirectory(at: bottle.clientDirectory, withIntermediateDirectories: true)
        precondition(Launcher.availableBottles(in: root).isEmpty)
        try Data().write(to: bottle.executable)
        let bottles = Launcher.availableBottles(in: root)
        precondition(bottles.count == 1 && bottles.first?.executable.path == bottle.executable.path)
        precondition(Launcher.availableBottles(in: temporary.appendingPathComponent("Unmounted")).isEmpty)
        let config = bottle.directory.appendingPathComponent("cxbottle.conf")
        let otherBottle = root.appendingPathComponent("另一個容器", isDirectory: true)
        try FileManager.default.createDirectory(at: otherBottle, withIntermediateDirectories: true)
        let otherConfig = otherBottle.appendingPathComponent("cxbottle.conf")
        let original = Data("[Bottle]\r\n\"Description\" = \"遊戲\"\r\n\"CX_GRAPHICS_BACKEND\" = \"outside\"\r\n[environmentvariables] ; comment\r\n\"WINEMSYNC\" = \"1\"\r\n\"cx_graphics_backend\" = \"d3dmetal\" ; manual choice\r\n".utf8)
        let expected = Data("[Bottle]\r\n\"Description\" = \"遊戲\"\r\n\"CX_GRAPHICS_BACKEND\" = \"outside\"\r\n[environmentvariables] ; comment\r\n\"WINEMSYNC\" = \"1\"\r\n\"CX_GRAPHICS_BACKEND\" = \"dxmt\" ; manual choice\r\n".utf8)
        try original.write(to: config)
        try original.write(to: otherConfig)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: config.path)

        let fixtureCrossOver = temporary.appendingPathComponent("CrossOver.app/Contents/SharedSupport/CrossOver")
        let fixtureWine = fixtureCrossOver.appendingPathComponent("bin/wine")
        try Launcher.configureGraphics(wine: fixtureWine, bottle: bottle, url: Launcher.gameURL)
        let withoutDriver = try Data(contentsOf: config)
        precondition(withoutDriver == original)

        let driver = fixtureCrossOver.appendingPathComponent("lib/dxmt")
        for relativePath in ["x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "x86_64-unix/winemetal.so"] {
            let file = driver.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        try Launcher.configureGraphics(wine: fixtureWine, bottle: bottle, url: "nxl://login/callback")
        try Launcher.configureGraphics(wine: fixtureWine, bottle: bottle, url: "nxl://play/12345")
        let afterCallbacks = try Data(contentsOf: config)
        precondition(afterCallbacks == original)

        if BottleGraphics.supportsDXMT(wine: fixtureWine) {
            try Launcher.configureGraphics(wine: fixtureWine, bottle: bottle, url: "NXL://play/59826")
        } else {
            try BottleGraphics.applyDXMT(to: bottle)
        }
        let saved = try Data(contentsOf: config)
        let untouched = try Data(contentsOf: otherConfig)
        let attributes = try FileManager.default.attributesOfItem(atPath: config.path)
        precondition(saved == expected && untouched == original)
        precondition(attributes[.posixPermissions] as? Int == 0o640)
        try BottleGraphics.applyDXMT(to: bottle)
        let secondWrite = try FileManager.default.attributesOfItem(atPath: config.path)
        precondition(secondWrite[.systemFileNumber] as? NSNumber == attributes[.systemFileNumber] as? NSNumber)

        let missingSection = "[Bottle]\n\"Template\" = \"win10_64\""
        precondition(BottleGraphics.configurationSelectingDXMT(missingSection) ==
            missingSection + "\n[EnvironmentVariables]\n\"CX_GRAPHICS_BACKEND\" = \"dxmt\"\n")
        let missingKey = "[EnvironmentVariables]\n;\"CX_GRAPHICS_BACKEND\" = \"auto\"\n[Other]\n"
        precondition(BottleGraphics.configurationSelectingDXMT(missingKey) ==
            "[EnvironmentVariables]\n;\"CX_GRAPHICS_BACKEND\" = \"auto\"\n\"CX_GRAPHICS_BACKEND\" = \"dxmt\"\n[Other]\n")

        try FileManager.default.removeItem(at: config)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: otherConfig)
        do {
            try BottleGraphics.applyDXMT(to: bottle)
            preconditionFailure("DXMT must not modify a linked configuration")
        } catch {
            let linkedTarget = try Data(contentsOf: otherConfig)
            precondition(linkedTarget == original)
        }
    } catch {
        fputs("FAIL: CrossOver bottle or DXMT configuration fixture\n", stderr)
        exit(1)
    }
    let bottle = NexonBottle(directory: URL(fileURLWithPath: "/example/External SSD/Bottle with spaces"), programFiles: "Program Files (x86)")
    let args = Launcher.arguments(bottle: bottle, url: sample)
    precondition(args.contains("--nxl=" + sample))
    precondition(Array(args.prefix(4)) == ["--bottle", "Bottle with spaces", "--scope", "private"])
    let inherited = ["CX_BOTTLE_PATH": "/wrong", "CX_INITIALIZED": "501:Bottle with spaces", "LANG": "en_US.UTF-8"]
    let environment = Launcher.environment(bottle: bottle, inherited: inherited)
    precondition(environment == ["CX_BOTTLE_PATH": "/example/External SSD", "LANG": "en_US.UTF-8"])
    precondition(Launcher.flags.allSatisfy(args.contains))
    precondition(args.last == "C:\\Program Files (x86)\\Nexon\\Nexon Launcher\\bin\\front_end")
    precondition(!args.contains("--no-sandbox"))
    print("PASS: URL validation, default/custom bottle discovery and name-based launch, argument boundaries, compatibility flags, automatic DXMT configuration")
    exit(0)
}
if CommandLine.arguments.contains("--check") {
    let wine = Launcher.wineURL()
    print("CrossOver found: \(wine != nil)")
    print("DXMT available: \(wine.map(BottleGraphics.supportsDXMT(wine:)) ?? false)")
    let root = Launcher.configuredBottleRoot()
    print("CrossOver bottle folder: \(root.path)")
    print("Nexon bottle found: \(!Launcher.availableBottles(in: root).isEmpty)")
    print("TCP buffer sufficient: \((Launcher.tcpBuffer() ?? 0) >= 1_000_000)")
    exit(0)
}
let delegate = NexonBridge()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
