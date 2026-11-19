import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import ServiceManagement
import os

enum ScannerStatus: Equatable {
    case starting
    case scanning
    case sleeping
    case permissionDenied
    case noCamera
    case failed(String)

    var title: String {
        switch self {
        case .starting: return "Starting camera…"
        case .scanning: return "Scanning"
        case .sleeping: return "Sleeping"
        case .permissionDenied: return "Camera access denied"
        case .noCamera: return "No camera found"
        case .failed(let message): return message
        }
    }
}

final class ScannerAppModel: ObservableObject {
    let settings: AppSettings
    let camera = CameraController()
    var session: AVCaptureSession { camera.session }
    var dismissPopover: (() -> Void)?

    @Published private(set) var status: ScannerStatus = .sleeping
    @Published private(set) var devices: [CameraDeviceInfo] = []
    @Published private(set) var activeCameraID: String?
    @Published private(set) var isAwake = false
    @Published private(set) var accessibilityTrusted = AccessibilityPermission.isGranted
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginError: String?
    @Published private(set) var hotkeyAvailable = true

    private let engine = ScanEngine()
    private let output = ScanOutput()
    private var hotkey: GlobalHotkey?
    private let logger = Logger(subsystem: "com.exweiv.barcodescanner", category: "app")

    private var idleWork: DispatchWorkItem?
    private var isPopoverOpen = false
    private var permissionRequested = false
    private var wasAwakeBeforeSystemSleep = false

    var needsAccessibility: Bool {
        settings.mode != .copy && !accessibilityTrusted
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        logger.notice("Starting app, camera: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue, privacy: .public), accessibility: \(AccessibilityPermission.isGranted, privacy: .public)")
        output.lastExternalApplication = { [weak self] in self?.lastExternalApplication }
        lastExternalApplication = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.lastExternalApplication = application
        }

        engine.onScan = { [weak self] result in
            DispatchQueue.main.async { self?.handleScan(result) }
        }

        camera.onCandidates = { [weak self] candidates in
            self?.engine.ingest(candidates)
        }
        camera.onRunningChanged = { [weak self] running in
            self?.cameraRunningChanged(running)
        }
        camera.onDevicesChanged = { [weak self] devices, activeID in
            self?.cameraDevicesChanged(devices, activeID: activeID)
        }
        camera.onError = { [weak self] message in
            self?.cameraFailed(message)
        }

        hotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey))
        hotkey?.onPress = { [weak self] in self?.toggleScanning() }
        hotkeyAvailable = hotkey != nil

        settings.$sleepInterval
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleIdle() }
            .store(in: &cancellables)

        requestCameraIfNeeded()
    }

    func toggleScanning() {
        if isAwake {
            sleepNow()
        } else {
            wake()
        }
    }

    func wake() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginScanning()
        case .notDetermined:
            requestCameraPermission()
        default:
            status = .permissionDenied
            isAwake = false
        }
    }

    func sleepNow() {
        logger.notice("Sleeping")
        isAwake = false
        cancelIdle()
        camera.stop()
        status = .sleeping
    }

    func popoverWillOpen() {
        isPopoverOpen = true
        cancelIdle()
        refreshPermissions()
        camera.refreshDevices()
        if !isAwake {
            wake()
        } else if case .failed = status {
            beginScanning()
        }
    }

    func popoverDidClose() {
        isPopoverOpen = false
        scheduleIdle()
    }

    func applicationDidBecomeActive() {
        refreshPermissions()
        camera.refreshDevices()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if isAwake, case .failed = status, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            beginScanning()
        }
    }

    func shutdown() {
        cancelIdle()
        camera.stopImmediately()
    }

    func systemWillSleep() {
        wasAwakeBeforeSystemSleep = isAwake
        sleepNow()
    }

    func systemDidWake() {
        guard wasAwakeBeforeSystemSleep else { return }
        wasAwakeBeforeSystemSleep = false
        wake()
    }

    func refreshPermissions() {
        accessibilityTrusted = AccessibilityPermission.isGranted
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
           status == .permissionDenied {
            wake()
        }
    }

    func selectCamera(id: String?) {
        settings.preferredCameraID = id
        camera.selectDevice(id: id)
        if !isAwake {
            wake()
        }
    }

    func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func requestCameraIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginScanning()
        case .notDetermined:
            requestCameraPermission()
        default:
            status = .permissionDenied
        }
    }

    private func requestCameraPermission() {
        guard !permissionRequested else {
            status = .starting
            return
        }
        permissionRequested = true
        status = .starting
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.beginScanning()
                } else {
                    self.status = .permissionDenied
                }
            }
        }
    }

    private func beginScanning() {
        logger.notice("Begin scanning")
        isAwake = true
        status = .starting
        camera.start(preferredDeviceID: settings.preferredCameraID)
        scheduleIdle()
    }

    private func handleScan(_ result: ScanResult) {
        logger.notice("Scanned \(result.symbology, privacy: .public)")
        scheduleIdle()
        output.deliver(
            result,
            mode: settings.mode,
            soundEnabled: settings.soundEnabled,
            dismissPopover: dismissPopover
        )
    }

    private func cameraRunningChanged(_ running: Bool) {
        if running {
            status = .scanning
            scheduleIdle()
        } else if isAwake {
            status = .failed("Camera stopped.")
        }
    }

    private func cameraDevicesChanged(_ devices: [CameraDeviceInfo], activeID: String?) {
        self.devices = devices
        activeCameraID = activeID

        if let preferred = settings.preferredCameraID,
           !devices.contains(where: { $0.id == preferred }) {
            settings.preferredCameraID = nil
        }

        if devices.isEmpty, isAwake {
            status = .noCamera
        }
    }

    private func cameraFailed(_ message: String) {
        logger.error("Camera failure: \(message, privacy: .public)")
        if devices.isEmpty {
            status = .noCamera
        } else if isAwake {
            status = .failed(message)
        }
    }

    private func scheduleIdle() {
        idleWork?.cancel()
        idleWork = nil

        guard isAwake, !isPopoverOpen else { return }
        let seconds = settings.sleepInterval.seconds
        guard seconds > 0 else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.sleepNow()
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelIdle() {
        idleWork?.cancel()
        idleWork = nil
    }

    private var cancellables = Set<AnyCancellable>()
    private var lastExternalApplication: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }
}
