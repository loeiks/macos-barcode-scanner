import Foundation
import os

final class ScanEngine {
    private let queue = DispatchQueue(label: "com.exweiv.barcodescanner.engine", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.exweiv.barcodescanner", category: "scan")

    private let confirmations = 2
    private let confirmationWindow: TimeInterval = 0.6
    private let repeatReleaseDelay: TimeInterval = 0.35
    private let emissionCooldown: TimeInterval = 0.5

    private var pendingValue: String?
    private var pendingSymbology = ""
    private var pendingCount = 0
    private var pendingLastSeen = Date.distantPast

    private var emittedValue: String?
    private var emittedLastSeen = Date.distantPast
    private var lastEmission = Date.distantPast

    var onScan: ((ScanResult) -> Void)?

    func ingest(_ candidates: [ScanCandidate], at now: Date = Date()) {
        queue.async {
            self.process(candidates, at: now)
        }
    }

    func reset() {
        queue.async {
            self.pendingValue = nil
            self.pendingCount = 0
            self.emittedValue = nil
        }
    }

    private func process(_ candidates: [ScanCandidate], at now: Date) {
        guard !candidates.isEmpty else {
            noteAbsence(at: now)
            return
        }

        var byValue: [String: ScanCandidate] = [:]
        for candidate in candidates {
            if let current = byValue[candidate.value] {
                if candidate.confidence > current.confidence {
                    byValue[candidate.value] = candidate
                }
            } else {
                byValue[candidate.value] = candidate
            }
        }

        guard let target = targetCandidate(from: byValue) else { return }

        if let emittedValue {
            if byValue[emittedValue] != nil {
                emittedLastSeen = now
                return
            }
            guard now.timeIntervalSince(emittedLastSeen) >= repeatReleaseDelay else { return }
            self.emittedValue = nil
        }

        if pendingValue == target.value, now.timeIntervalSince(pendingLastSeen) <= confirmationWindow {
            pendingCount += 1
        } else {
            pendingValue = target.value
            pendingSymbology = target.symbology
            pendingCount = 1
        }
        pendingLastSeen = now

        guard pendingCount >= confirmations else { return }
        guard now.timeIntervalSince(lastEmission) >= emissionCooldown else { return }

        pendingValue = nil
        pendingCount = 0
        emittedValue = target.value
        emittedLastSeen = now
        lastEmission = now

        logger.debug("Emitted \(target.symbology, privacy: .public) code with \(target.value.count, privacy: .public) characters")
        onScan?(ScanResult(value: target.value, symbology: target.symbology))
    }

    private func noteAbsence(at now: Date) {
        if emittedValue != nil, now.timeIntervalSince(emittedLastSeen) >= repeatReleaseDelay {
            emittedValue = nil
        }
        if pendingValue != nil, now.timeIntervalSince(pendingLastSeen) > confirmationWindow {
            pendingValue = nil
            pendingCount = 0
        }
    }

    private func targetCandidate(from byValue: [String: ScanCandidate]) -> ScanCandidate? {
        if let pendingValue, let pending = byValue[pendingValue] {
            return pending
        }
        return byValue.values.max { lhs, rhs in
            if abs(lhs.confidence - rhs.confidence) > 0.05 {
                return lhs.confidence < rhs.confidence
            }
            if lhs.area != rhs.area {
                return lhs.area < rhs.area
            }
            return lhs.distanceFromCenter > rhs.distanceFromCenter
        }
    }
}
