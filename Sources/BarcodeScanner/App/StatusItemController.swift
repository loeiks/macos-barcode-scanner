import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model: ScannerAppModel
    private var cancellables = Set<AnyCancellable>()
    private var lastClose = Date.distantPast

    init(model: ScannerAppModel) {
        self.model = model
        super.init()

        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model, settings: model.settings)
        )
        popover.contentSize = NSSize(width: 340, height: 600)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.image = Self.statusImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
        }

        model.dismissPopover = { [weak self] in
            self?.popover.performClose(nil)
        }

        Publishers.CombineLatest3(model.$status, model.$accessibilityTrusted, model.settings.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        updateStatusItem()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // A transient popover closes on the same click that lands on the status
        // item, so ignore that close and only reopen on a deliberate next click.
        guard Date().timeIntervalSince(lastClose) > 0.2 else { return }

        model.popoverWillOpen()
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        model.popoverDidClose()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let isWarning: Bool
        switch model.status {
        case .permissionDenied, .noCamera, .failed:
            isWarning = true
        default:
            isWarning = false
        }

        let needsAccessibility = model.needsAccessibility
        button.image = Self.statusImage()
        button.contentTintColor = (isWarning || needsAccessibility) ? .systemOrange : nil
        button.appearsDisabled = (model.status == .sleeping || model.status == .starting) && !isWarning
        button.toolTip = tooltip(isWarning: isWarning, needsAccessibility: needsAccessibility)
    }

    private func tooltip(isWarning: Bool, needsAccessibility: Bool) -> String {
        if isWarning {
            return "Barcode Scanner — \(model.status.title)"
        }
        if needsAccessibility {
            return "Barcode Scanner — Accessibility permission needed for paste"
        }
        return "Barcode Scanner — \(model.status.title)"
    }

    private static func statusImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "barcode", accessibilityDescription: "Barcode Scanner")
        image?.isTemplate = true
        return image
    }
}
