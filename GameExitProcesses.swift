import AppKit
import Darwin

struct WatchedProcess: Hashable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct GameExitSnapshot {
    let games: Set<WatchedProcess>
    let launchers: Set<WatchedProcess>

    var soleIdleLauncher: WatchedProcess? {
        games.isEmpty && launchers.count == 1 ? launchers.first : nil
    }
}

enum NexonClientInvocation {
    // KERN_PROCARGS2 contains an exec path, alignment NULs, argc arguments, then environment data.
    // Compare known bytes in place and never turn an arbitrary argument into a String.
    static func isLegacy(_ bytes: UnsafeRawBufferPointer, bottle: NexonBottle) -> Bool {
        let wordSize = MemoryLayout<Int32>.size
        guard bytes.count > wordSize, bytes[wordSize] == UInt8(ascii: "/") else { return false }
        var count: Int32 = 0
        withUnsafeMutableBytes(of: &count) { $0.copyBytes(from: bytes.prefix(wordSize)) }
        guard count == 3 else { return false }

        var cursor = wordSize
        while cursor < bytes.count && bytes[cursor] != 0 { cursor += 1 }
        while cursor < bytes.count && bytes[cursor] == 0 { cursor += 1 }
        var arguments: [Range<Int>] = []
        for _ in 0..<count {
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 0 { cursor += 1 }
            guard cursor < bytes.count else { return false }
            arguments.append(start..<cursor)
            cursor += 1
        }

        return bytes[arguments[0]].elementsEqual(bottle.windowsClient.utf8) &&
            bytes[arguments[1]].elementsEqual(bottle.windowsFrontEnd.utf8) && arguments[2].isEmpty
    }
}

struct GameExitProcesses {
    private enum Executable {
        case missing, unknown, available(URL)
    }

    private enum ProcessStatus {
        case gone, unknown, running(uid_t, WatchedProcess)
    }

    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private let bottle: NexonBottle
    private let bottleDirectory: URL
    private let wineRoots: [URL]
    private let wineEntry: URL
    private let wineLoaderFiles: Set<FileIdentity>
    private let userTemporaryDirectory: URL?
    private static let wineNames = ["wine", "wine64", "wine-preloader", "wine64-preloader", "wineloader"]

    init(bottle: NexonBottle, wine: URL) {
        self.bottle = bottle
        bottleDirectory = Self.canonical(bottle.directory)
        let crossOver = wine.deletingLastPathComponent().deletingLastPathComponent()
        wineRoots = ["lib/wine", "lib64/wine"].map { Self.canonical(crossOver.appendingPathComponent($0)) }
        wineEntry = Self.canonical(wine)
        let loaderDirectories = wineRoots.flatMap { root in
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return [root] + children.filter { $0.lastPathComponent.hasSuffix("-unix") && Self.isWithin(Self.canonical($0), root) }
        }
        let loaderPaths = loaderDirectories.flatMap { directory in
            Self.wineNames.map { directory.appendingPathComponent($0) }
        }
        wineLoaderFiles = Set(([wineEntry] + loaderPaths).compactMap(Self.regularFileIdentity))
        userTemporaryDirectory = Self.systemTemporaryDirectory()
    }

    func snapshot() -> GameExitSnapshot? {
        guard case let .available(launcher) = executable(at: bottle.executable),
              let launchers = processes(mapping: launcher, requireLauncherApplication: true) else { return nil }
        switch executable(at: bottle.taiwanGameExecutable) {
        case let .available(game):
            guard let games = processes(mapping: game, requireLauncherApplication: false) else { return nil }
            return GameExitSnapshot(games: games, launchers: launchers)
        case .missing:
            return GameExitSnapshot(games: [], launchers: launchers)
        case .unknown:
            return nil
        }
    }

    func hasExited(_ identity: WatchedProcess) -> Bool {
        switch Self.status(of: identity.pid) {
        case .gone: return true
        case .unknown: return false
        case let .running(_, now): return now != identity
        }
    }

    func permitsCleanup() -> Bool {
        guard case let .available(game) = executable(at: bottle.taiwanGameExecutable) else { return false }
        return hasDedicatedLibrary(game.deletingLastPathComponent().deletingLastPathComponent(), allowMissing: false)
    }

    private func hasDedicatedLibrary(_ gameDirectory: URL, allowMissing: Bool) -> Bool {
        let library = Self.canonical(bottle.directory.appendingPathComponent("drive_c/Nexon/Library", isDirectory: true))
        guard Self.isWithin(library, bottleDirectory), gameDirectory.deletingLastPathComponent().path == library.path else { return false }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: library,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        } catch let error as CocoaError {
            return allowMissing && (error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile)
        } catch { return false }
        let gameDirectoryName = gameDirectory.lastPathComponent
        guard allowMissing || entries.contains(where: { $0.lastPathComponent == gameDirectoryName }) else { return false }
        // Nexon can manage other games in the same bottle. Any other library directory or link is ambiguous.
        return entries.allSatisfy { entry in
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink == false else { return false }
            return entry.lastPathComponent == gameDirectoryName ? values.isDirectory == true : values.isRegularFile == true
        }
    }

    func requestQuit(_ identity: WatchedProcess, force: Bool) {
        guard permitsCleanup(), snapshot()?.soleIdleLauncher == identity,
              let application = launcherApplication(pid: identity.pid), isCurrent(identity) else { return }
        // Target only this Launch Services application, including when the process ignores a normal quit request.
        if force { _ = application.forceTerminate() } else { _ = application.terminate() }
    }

    func legacyLauncher() -> WatchedProcess? {
        guard allowsLegacyRestart(), let identity = snapshot()?.soleIdleLauncher,
              isLegacyInvocation(of: identity) else { return nil }
        return identity
    }

    func requestLegacyQuit(_ identity: WatchedProcess) -> Bool {
        guard legacyLauncher() == identity, let application = launcherApplication(pid: identity.pid),
              isCurrent(identity) else { return false }
        return application.terminate()
    }

    func canRelaunchAfterLegacyQuit(_ identity: WatchedProcess) -> Bool {
        guard hasExited(identity), allowsLegacyRestart(), let current = snapshot() else { return false }
        return current.games.isEmpty && current.launchers.isEmpty
    }

    private func allowsLegacyRestart() -> Bool {
        switch executable(at: bottle.taiwanGameExecutable) {
        case let .available(game):
            return hasDedicatedLibrary(game.deletingLastPathComponent().deletingLastPathComponent(), allowMissing: false)
        case .missing:
            let directory = Self.canonical(bottle.taiwanGameExecutable.deletingLastPathComponent().deletingLastPathComponent())
            return hasDedicatedLibrary(directory, allowMissing: true)
        case .unknown:
            return false
        }
    }

    private func isCurrent(_ identity: WatchedProcess) -> Bool {
        guard case let .running(uid, live) = Self.status(of: identity.pid) else { return false }
        return uid == getuid() && live == identity
    }

    private func isLegacyInvocation(of identity: WatchedProcess) -> Bool {
        guard isCurrent(identity) else { return false }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, identity.pid]
        var count = 0
        guard sysctl(&mib, 3, nil, &count, nil, 0) == 0, (1...1_048_576).contains(count) else { return false }
        var bytes = [UInt8](repeating: 0, count: count)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let pointer = buffer.baseAddress else { return false }
            defer { _ = memset_s(pointer, buffer.count, 0, buffer.count) }
            guard sysctl(&mib, 3, pointer, &count, nil, 0) == 0, (1...buffer.count).contains(count),
                  isCurrent(identity) else { return false }
            return NexonClientInvocation.isLegacy(UnsafeRawBufferPointer(start: pointer, count: count), bottle: bottle)
        }
    }

    private func executable(at file: URL) -> Executable {
        let resolved = Self.canonical(file)
        guard Self.isWithin(resolved, bottleDirectory), resolved.lastPathComponent == file.lastPathComponent else { return .unknown }
        var info = stat()
        if resolved.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) != 0 {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unknown
        }
        return (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) && info.st_size > 0 ? .available(resolved) : .unknown
    }

    private func processes(mapping executable: URL, requireLauncherApplication: Bool) -> Set<WatchedProcess>? {
        guard let pids = Self.pids(mapping: executable) else { return nil }
        var found = Set<WatchedProcess>()
        for pid in pids {
            switch Self.status(of: pid) {
            case .gone: continue
            case .unknown: return nil
            case let .running(uid, identity):
                guard uid == getuid() else { continue }
                guard let host = Self.hostExecutable(of: pid) else {
                    if hasExited(identity) { continue }
                    return nil
                }
                guard isWineHost(host) else { continue }
                guard let workingDirectory = Self.workingDirectory(of: pid) else {
                    if hasExited(identity) { continue }
                    return nil
                }
                guard Self.isWithin(workingDirectory, bottleDirectory),
                      !requireLauncherApplication || launcherApplication(pid: pid) != nil else { continue }
                found.insert(identity)
            }
        }
        return found
    }

    private func isWineHost(_ host: URL) -> Bool {
        if host.path == wineEntry.path ||
            (Self.wineNames.contains(host.lastPathComponent) && wineRoots.contains(where: { Self.isWithin(host, $0) })) {
            return true
        }
        // CrossOver can give a hard link to its Wine loader the Windows application's name.
        let parent = host.deletingLastPathComponent()
        guard let userTemporaryDirectory, parent.lastPathComponent.hasPrefix("winetemp-"),
              parent.deletingLastPathComponent().path == userTemporaryDirectory.path,
              let identity = Self.regularFileIdentity(host) else { return false }
        return wineLoaderFiles.contains(identity)
    }

    private static func regularFileIdentity(_ file: URL) -> FileIdentity? {
        var info = stat()
        guard file.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return nil }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private static func systemTemporaryDirectory() -> URL? {
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard size > 1, size <= Int(PATH_MAX) else { return nil }
        var path = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &path, size) == size else { return nil }
        return canonical(URL(fileURLWithPath: String(cString: path), isDirectory: true))
    }

    private func launcherApplication(pid: pid_t) -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: pid), !application.isTerminated,
              application.activationPolicy == .regular,
              application.executableURL?.lastPathComponent.lowercased() == bottle.executable.lastPathComponent.lowercased() else { return nil }
        return application
    }

    private static func canonical(_ url: URL) -> URL {
        let absolute = url.standardizedFileURL
        if let path = absolute.path.withCString({ realpath($0, nil) }) {
            defer { free(path) }
            return URL(fileURLWithPath: String(cString: path))
        }
        let error = errno
        let parent = absolute.deletingLastPathComponent()
        guard error == ENOENT, parent.path != absolute.path, !parent.path.isEmpty else {
            return absolute
        }
        // First-time launch can precede creation of Nexon/Library. Resolve its existing ancestors too.
        return canonical(parent).appendingPathComponent(absolute.lastPathComponent)
    }

    private static func isWithin(_ url: URL, _ directory: URL) -> Bool {
        url.pathComponents.starts(with: directory.pathComponents)
    }

    private static func pids(mapping file: URL) -> [pid_t]? {
        file.path.withCString { path in
            let type = UInt32(PROC_UID_ONLY), flags = UInt32(PROC_LISTPIDSPATH_EXCLUDE_EVTONLY)
            let stride = MemoryLayout<pid_t>.stride
            let estimatedBytes = proc_listpidspath(type, getuid(), path, flags, nil, 0)
            guard estimatedBytes >= 0 else { return nil }
            var capacity = Int(estimatedBytes) / stride + 32
            for _ in 0..<2 {
                var pids = [pid_t](repeating: 0, count: capacity)
                let countBytes = pids.withUnsafeMutableBytes { buffer in
                    proc_listpidspath(type, getuid(), path, flags, buffer.baseAddress, Int32(buffer.count))
                }
                guard countBytes >= 0, Int(countBytes).isMultiple(of: stride) else { return nil }
                let count = Int(countBytes) / stride
                if count < capacity { return pids.prefix(count).filter { $0 > 0 } }
                capacity *= 2
            }
            return nil
        }
    }

    private static func status(of pid: pid_t) -> ProcessStatus {
        guard pid > 0 else { return .unknown }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard bytes == size, info.pbi_pid == UInt32(pid) else { return errno == ESRCH ? .gone : .unknown }
        if info.pbi_status == UInt32(SZOMB) { return .gone }
        return .running(info.pbi_uid, WatchedProcess(pid: pid, startSeconds: info.pbi_start_tvsec,
                                                   startMicroseconds: info.pbi_start_tvusec))
    }

    private static func hostExecutable(of pid: pid_t) -> URL? {
        // libproc uses four PATH_MAX units for its executable path buffer.
        var path = [CChar](repeating: 0, count: 4 * Int(PATH_MAX))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return canonical(URL(fileURLWithPath: String(cString: path)))
    }

    private static func workingDirectory(of pid: pid_t) -> URL? {
        var vnode = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, size) == size else { return nil }
        let path = withUnsafeBytes(of: &vnode.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        guard path.hasPrefix("/") else { return nil }
        return canonical(URL(fileURLWithPath: path, isDirectory: true))
    }
}
