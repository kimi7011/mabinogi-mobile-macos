import Foundation

struct GameExitTracker {
    enum Action: Equatable {
        case wait
        case quit(WatchedProcess)
        case forceQuit(WatchedProcess)
        case finish
    }

    private var games: Set<WatchedProcess> = []
    private var launchers: Set<WatchedProcess> = []
    private var waitForLaunchUntil: TimeInterval
    private var lastSnapshotAt: TimeInterval
    private var gameMissingSince: TimeInterval?
    private var quitRequest: (launcher: WatchedProcess, time: TimeInterval)?
    private var forceRequestedAt: TimeInterval?

    init(now: TimeInterval) {
        waitForLaunchUntil = now + 45
        lastSnapshotAt = now
    }

    mutating func advance(_ snapshot: GameExitSnapshot?, now: TimeInterval,
                          hasExited: (WatchedProcess) -> Bool, permitsCleanup: () -> Bool) -> Action {
        guard let snapshot else {
            gameMissingSince = nil
            if now - lastSnapshotAt >= 45 { return .finish }
            return games.isEmpty && now >= waitForLaunchUntil ? .finish : .wait
        }
        lastSnapshotAt = now
        if !snapshot.games.isEmpty {
            games.formUnion(snapshot.games)
            launchers.formUnion(snapshot.launchers)
            clearExitTimers()
            return .wait
        }

        if games.isEmpty {
            // Keep watching while Nexon is installing, downloading or waiting for sign-in.
            if !snapshot.launchers.isEmpty { waitForLaunchUntil = now + 45 }
            return now >= waitForLaunchUntil ? .finish : .wait
        }
        guard games.allSatisfy(hasExited) else {
            clearExitTimers()
            return .wait
        }

        if gameMissingSince == nil { gameMissingSince = now }
        guard let missingSince = gameMissingSince, now - missingSince >= 6 else { return .wait }
        let remaining = snapshot.launchers
        guard remaining.count == 1, let launcher = remaining.first, launchers.contains(launcher),
              permitsCleanup() else { return .finish }

        if let forcedAt = forceRequestedAt { return now - forcedAt >= 4 ? .finish : .wait }
        if let request = quitRequest {
            guard request.launcher == launcher else { return .finish }
            guard now - request.time >= 5 else { return .wait }
            forceRequestedAt = now
            return .forceQuit(launcher)
        }
        quitRequest = (launcher, now)
        return .quit(launcher)
    }

    private mutating func clearExitTimers() {
        gameMissingSince = nil
        quitRequest = nil
        forceRequestedAt = nil
    }
}

final class GameExitMonitor {
    private let processes: GameExitProcesses
    private var tracker: GameExitTracker
    private var timer: Timer?

    init(bottle: NexonBottle, wine: URL) {
        processes = GameExitProcesses(bottle: bottle, wine: wine)
        tracker = GameExitTracker(now: ProcessInfo.processInfo.systemUptime)
    }

    func start(onFinish: @escaping () -> Void) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let action = self.tracker.advance(self.processes.snapshot(), now: ProcessInfo.processInfo.systemUptime,
                                              hasExited: self.processes.hasExited,
                                              permitsCleanup: self.processes.permitsCleanup)
            switch action {
            case .wait: break
            case .quit(let launcher): self.processes.requestQuit(launcher, force: false)
            case .forceQuit(let launcher): self.processes.requestQuit(launcher, force: true)
            case .finish:
                self.stop()
                onFinish()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
