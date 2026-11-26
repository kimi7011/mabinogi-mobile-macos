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
        let gameDirectory = game.deletingLastPathComponent().deletingLastPathComponent()
        let library = Self.canonical(bottle.directory.appendingPathComponent("drive_c/Nexon/Library", isDirectory: true))
        guard Self.isWithin(library, bottleDirectory), gameDirectory.deletingLastPathComponent().path == library.path,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: library, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              entries.contains(where: { $0.path == gameDirectory.path }) else { return false }
        // Nexon can manage other games in the same bottle. Any other library directory or link is ambiguous.
        return entries.allSatisfy { entry in
            if entry.path == gameDirectory.path { return true }
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink == false
        }
    }

    func requestQuit(_ identity: WatchedProcess, force: Bool) {
        guard permitsCleanup(), let current = snapshot(),
              current.games.isEmpty, current.launchers == [identity],
              let application = launcherApplication(pid: identity.pid),
              case let .running(uid, live) = Self.status(of: identity.pid), uid == getuid(), live == identity else { return }
        // Target only this Launch Services application, including when the process ignores a normal quit request.
        if force { _ = application.forceTerminate() } else { _ = application.terminate() }
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

    private static func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

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
