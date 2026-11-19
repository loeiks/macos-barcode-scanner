import Foundation
import Combine

enum OutputMode: String, CaseIterable, Identifiable {
    case copy
    case paste
    case pasteAndEnter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .pasteAndEnter: return "Paste + Enter"
        }
    }

    var detail: String {
        switch self {
        case .copy: return "Copy the scanned code to the clipboard."
        case .paste: return "Copy and paste into the focused app."
        case .pasteAndEnter: return "Copy, paste, then press Return."
        }
    }
}

enum SleepInterval: String, CaseIterable, Identifiable {
    case thirtySeconds = "30"
    case oneMinute = "60"
    case twoMinutes = "120"
    case fiveMinutes = "300"
    case never = "0"

    var id: String { rawValue }

    var seconds: TimeInterval { TimeInterval(Double(rawValue) ?? 0) }

    var title: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .never: return "Never"
        }
    }
}

final class AppSettings: ObservableObject {
    private enum Key {
        static let mode = "outputMode"
        static let soundEnabled = "soundEnabled"
        static let sleepSeconds = "sleepSeconds"
        static let preferredCameraID = "preferredCameraID"
    }

    private let defaults: UserDefaults

    @Published var mode: OutputMode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var sleepInterval: SleepInterval { didSet { defaults.set(sleepInterval.rawValue, forKey: Key.sleepSeconds) } }
    @Published var preferredCameraID: String? { didSet { defaults.set(preferredCameraID, forKey: Key.preferredCameraID) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = OutputMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .paste
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        sleepInterval = SleepInterval(rawValue: defaults.string(forKey: Key.sleepSeconds) ?? "") ?? .oneMinute
        preferredCameraID = defaults.string(forKey: Key.preferredCameraID)
    }
}
