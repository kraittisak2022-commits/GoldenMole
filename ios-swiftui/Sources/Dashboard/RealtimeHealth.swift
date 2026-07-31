import Foundation
import Observation
import OSLog
import SwiftUI

/// Times Real-time snapshot builds and switches to economy mode after repeated slow builds.
@MainActor
@Observable
final class RealtimeBuildSupervisor {
    static let shared = RealtimeBuildSupervisor()

    private static let budgetMs: Double = 350
    private static let slowStreakLimit = 2

    private(set) var lastBuildMs: Double = 0
    private(set) var consecutiveSlowBuilds = 0
    private(set) var isEconomyMode = false
    private(set) var isBuilding = false
    /// True while a build has been running longer than 1s (avoids flicker on fast builds).
    private(set) var showBuildingChip = false

    @ObservationIgnored private var buildingChipTask: Task<Void, Never>?

    func beginBuild() {
        isBuilding = true
        showBuildingChip = false
        buildingChipTask?.cancel()
        buildingChipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, isBuilding else { return }
            showBuildingChip = true
        }
    }

    func endBuild(durationMs: Double, light: Bool) {
        buildingChipTask?.cancel()
        buildingChipTask = nil
        isBuilding = false
        showBuildingChip = false
        lastBuildMs = durationMs

        if light {
            return
        }
        if durationMs > Self.budgetMs {
            consecutiveSlowBuilds += 1
            if consecutiveSlowBuilds >= Self.slowStreakLimit, !isEconomyMode {
                isEconomyMode = true
                ErrorReportCenter.shared.reportMessage(
                    "Real-time สลับโหมดประหยัด (build \(Int(durationMs))ms)",
                    detail: "งบ \(Int(Self.budgetMs))ms · ช้าติดกัน \(consecutiveSlowBuilds) ครั้ง",
                    source: "perf",
                    screenPage: "realtimeV4"
                )
            }
        } else {
            consecutiveSlowBuilds = 0
        }
    }

    func exitEconomyMode() {
        isEconomyMode = false
        consecutiveSlowBuilds = 0
    }

    /// Off-main timed build with Instruments signpost.
    nonisolated static func measureBuild<T>(_ work: () -> T) -> (T, Double) {
        let signposter = OSSignposter(subsystem: "com.goldenmole.dashboard", category: "realtime")
        let state = signposter.beginInterval("snapshot.build")
        let clock = ContinuousClock()
        let start = clock.now
        let result = work()
        let elapsed = start.duration(to: clock.now)
        let elapsedMs = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        signposter.endInterval("snapshot.build", state)
        return (result, elapsedMs)
    }
}

/// Background pinger that detects main-thread hangs while Real-time is visible.
@MainActor
@Observable
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private static let pingIntervalMs: UInt64 = 500
    private static let hangThresholdMs: Double = 1_500

    private(set) var hangCount = 0
    private(set) var lastHangMs: Double = 0

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var running = false

    func start() {
        guard !running else { return }
        running = true
        loopTask?.cancel()
        loopTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let sent = ContinuousClock.now
                await MainActor.run {
                    let elapsed = sent.duration(to: ContinuousClock.now)
                    let ms = Double(elapsed.components.seconds) * 1000
                        + Double(elapsed.components.attoseconds) / 1e15
                    self?.notePing(latencyMs: ms)
                }
                try? await Task.sleep(nanoseconds: Self.pingIntervalMs * 1_000_000)
            }
        }
    }

    func stop() {
        running = false
        loopTask?.cancel()
        loopTask = nil
    }

    private func notePing(latencyMs: Double) {
        guard latencyMs >= Self.hangThresholdMs else { return }
        hangCount += 1
        lastHangMs = latencyMs
        ErrorReportCenter.shared.reportMessage(
            "Real-time เมนเธรดค้าง \(Int(latencyMs))ms",
            detail: "hangCount=\(hangCount)",
            source: "perf",
            screenPage: "realtimeV4"
        )
    }
}
