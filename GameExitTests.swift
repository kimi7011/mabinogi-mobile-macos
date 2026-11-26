import Foundation

func testGameExitTracker() {
    let game = WatchedProcess(pid: 101, startSeconds: 100, startMicroseconds: 1)
    let replacement = WatchedProcess(pid: 102, startSeconds: 110, startMicroseconds: 1)
    let launcher = WatchedProcess(pid: 201, startSeconds: 90, startMicroseconds: 1)
    let reusedLauncherPID = WatchedProcess(pid: 201, startSeconds: 90, startMicroseconds: 2)
    let otherLauncher = WatchedProcess(pid: 202, startSeconds: 90, startMicroseconds: 1)
    let empty = GameExitSnapshot(games: [], launchers: [])
    let launcherOnly = GameExitSnapshot(games: [], launchers: [launcher])
    let playing = GameExitSnapshot(games: [game], launchers: [launcher])
    let playingAgain = GameExitSnapshot(games: [replacement], launchers: [launcher])

    func expect(_ tracker: inout GameExitTracker, _ snapshot: GameExitSnapshot?, at time: TimeInterval,
                _ expected: GameExitTracker.Action, stillRunning: Set<WatchedProcess> = [],
                cleanupAllowed: Bool = true, file: StaticString = #fileID, line: UInt = #line) {
        let action = tracker.advance(snapshot, now: time, hasExited: { !stillRunning.contains($0) },
                                     permitsCleanup: { cleanupAllowed })
        precondition(action == expected, "At time \(time), expected \(expected), got \(action)", file: file, line: line)
    }

    // An idle request expires. An open launcher may be waiting for sign-in or a download.
    var idle = GameExitTracker(now: 0)
    expect(&idle, empty, at: 44, .wait)
    expect(&idle, empty, at: 45, .finish)
    var signIn = GameExitTracker(now: 0)
    expect(&signIn, launcherOnly, at: 10, .wait)
    expect(&signIn, launcherOnly, at: 54, .wait)
    expect(&signIn, launcherOnly, at: 98, .wait)
    expect(&signIn, empty, at: 142, .wait)
    expect(&signIn, empty, at: 143, .finish)

    // Observe a game before arming cleanup. Escalate only after both grace periods.
    var closing = GameExitTracker(now: 0)
    expect(&closing, playing, at: 1, .wait)
    expect(&closing, launcherOnly, at: 2, .wait)
    expect(&closing, launcherOnly, at: 7.9, .wait)
    expect(&closing, launcherOnly, at: 8, .quit(launcher))
    expect(&closing, launcherOnly, at: 12.9, .wait)
    expect(&closing, launcherOnly, at: 13, .forceQuit(launcher))
    expect(&closing, launcherOnly, at: 16.9, .wait)
    expect(&closing, launcherOnly, at: 17, .finish)

    var graceful = GameExitTracker(now: 0)
    expect(&graceful, playing, at: 1, .wait)
    expect(&graceful, launcherOnly, at: 2, .wait)
    expect(&graceful, launcherOnly, at: 8, .quit(launcher))
    expect(&graceful, empty, at: 9, .finish)

    // A replacement game seen before or after a quit cancels the previous exit timers.
    var beforeQuit = GameExitTracker(now: 0)
    expect(&beforeQuit, playing, at: 1, .wait)
    expect(&beforeQuit, launcherOnly, at: 2, .wait)
    expect(&beforeQuit, playingAgain, at: 7, .wait)
    expect(&beforeQuit, launcherOnly, at: 8, .wait)
    expect(&beforeQuit, launcherOnly, at: 13.9, .wait)
    expect(&beforeQuit, launcherOnly, at: 14, .quit(launcher))

    var afterQuit = GameExitTracker(now: 0)
    expect(&afterQuit, playing, at: 1, .wait)
    expect(&afterQuit, launcherOnly, at: 2, .wait)
    expect(&afterQuit, launcherOnly, at: 8, .quit(launcher))
    expect(&afterQuit, playingAgain, at: 9, .wait)
    expect(&afterQuit, launcherOnly, at: 13, .wait, stillRunning: [replacement])
    expect(&afterQuit, launcherOnly, at: 14, .wait)
    expect(&afterQuit, launcherOnly, at: 20, .quit(launcher))

    // Cleanup requires one launcher seen with the game, and an unshared, verified scope.
    var unknownLauncher = GameExitTracker(now: 0)
    expect(&unknownLauncher, GameExitSnapshot(games: [game], launchers: []), at: 1, .wait)
    expect(&unknownLauncher, launcherOnly, at: 2, .wait)
    expect(&unknownLauncher, launcherOnly, at: 8, .finish)

    var ambiguous = GameExitTracker(now: 0)
    expect(&ambiguous, playing, at: 1, .wait)
    expect(&ambiguous, launcherOnly, at: 2, .wait)
    expect(&ambiguous, GameExitSnapshot(games: [], launchers: [launcher, otherLauncher]), at: 8, .finish)

    var sharedScope = GameExitTracker(now: 0)
    expect(&sharedScope, playing, at: 1, .wait, cleanupAllowed: false)
    expect(&sharedScope, launcherOnly, at: 2, .wait, cleanupAllowed: false)
    expect(&sharedScope, launcherOnly, at: 8, .finish, cleanupAllowed: false)

    var reusedPID = GameExitTracker(now: 0)
    expect(&reusedPID, playing, at: 1, .wait)
    expect(&reusedPID, launcherOnly, at: 2, .wait)
    expect(&reusedPID, launcherOnly, at: 8, .quit(launcher))
    expect(&reusedPID, GameExitSnapshot(games: [], launchers: [reusedLauncherPID]), at: 13, .finish)

    // Unknown snapshots break the evidence chain and cannot cause a force-quit.
    var unavailable = GameExitTracker(now: 0)
    expect(&unavailable, playing, at: 1, .wait)
    expect(&unavailable, launcherOnly, at: 2, .wait)
    expect(&unavailable, nil, at: 8, .wait)
    expect(&unavailable, launcherOnly, at: 9, .wait)
    expect(&unavailable, launcherOnly, at: 15, .quit(launcher))
    expect(&unavailable, nil, at: 20, .wait)
    expect(&unavailable, launcherOnly, at: 21, .wait)
    expect(&unavailable, launcherOnly, at: 26.9, .wait)
    expect(&unavailable, launcherOnly, at: 27, .forceQuit(launcher))

    var unavailableTooLong = GameExitTracker(now: 0)
    expect(&unavailableTooLong, playing, at: 1, .wait)
    expect(&unavailableTooLong, launcherOnly, at: 2, .wait)
    expect(&unavailableTooLong, launcherOnly, at: 8, .quit(launcher))
    expect(&unavailableTooLong, nil, at: 52.9, .wait)
    expect(&unavailableTooLong, nil, at: 53, .finish)

    var missingMapping = GameExitTracker(now: 0)
    expect(&missingMapping, playing, at: 1, .wait)
    expect(&missingMapping, launcherOnly, at: 2, .wait, stillRunning: [game])
    expect(&missingMapping, launcherOnly, at: 60, .wait, stillRunning: [game])
    expect(&missingMapping, launcherOnly, at: 61, .wait)
    expect(&missingMapping, launcherOnly, at: 66.9, .wait)
    expect(&missingMapping, launcherOnly, at: 67, .quit(launcher))
}
