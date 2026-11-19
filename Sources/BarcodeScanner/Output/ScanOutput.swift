import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func request() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}

final class ScanOutput {
    private var sound: NSSound?
    var lastExternalApplication: (() -> NSRunningApplication?)?

    func deliver(
        _ result: ScanResult,
        mode: OutputMode,
        soundEnabled: Bool,
        dismissPopover: (() -> Void)?
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.value, forType: .string)

        if soundEnabled {
            play()
        }

        guard mode != .copy else { return }
        guard AccessibilityPermission.isGranted else { return }

        dismissPopover?()

        guard NSApp.isActive else {
            postPaste(pressEnter: mode == .pasteAndEnter)
            return
        }

        guard let application = lastExternalApplication?(), !application.isTerminated else { return }
        application.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.postPaste(pressEnter: mode == .pasteAndEnter)
        }
    }

    private func play() {
        let name = NSSound.Name("Tink")
        if sound?.name != name {
            sound = NSSound(named: name)
        }
        sound?.stop()
        sound?.play()
    }

    private func postPaste(pressEnter: Bool) {
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        guard pressEnter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            self.postKey(CGKeyCode(kVK_Return), flags: [])
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}
