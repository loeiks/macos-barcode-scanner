import AVFoundation
import CoreMedia
import Vision
import os

struct CameraDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
}

final class CameraController: NSObject {
    let session = AVCaptureSession()

    var onCandidates: (([ScanCandidate]) -> Void)?
    var onDevicesChanged: (([CameraDeviceInfo], String?) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.exweiv.barcodescanner.session")
    private let videoQueue = DispatchQueue(label: "com.exweiv.barcodescanner.video", qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "com.exweiv.barcodescanner.metadata", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.exweiv.barcodescanner", category: "camera")

    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let metadataLock = NSLock()
    private var metadataCandidates: [ScanCandidate] = []
    private var metadataTimestamp = Date.distantPast

    private var currentInput: AVCaptureDeviceInput?
    private var currentDeviceID: String?
    private var outputsConfigured = false
    private var desiredRunning = false
    private var visionRequest: VNDetectBarcodesRequest?
    private var retryCount = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(deviceWasConnected),
            name: AVCaptureDevice.wasConnectedNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(deviceWasDisconnected),
            name: AVCaptureDevice.wasDisconnectedNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification, object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(preferredDeviceID: String?) {
        sessionQueue.async {
            self.desiredRunning = true
            self.ensureConfigured(preferredDeviceID: preferredDeviceID)
            guard self.currentInput != nil else { return }
            guard !self.session.isRunning else {
                self.notifyRunning(true)
                return
            }
            self.session.startRunning()
            self.logger.notice("Capture session running: \(self.session.isRunning, privacy: .public)")
            if self.session.isRunning {
                self.retryCount = 0
                self.configureOutputs()
            }
            self.notifyRunning(self.session.isRunning)
            self.notifyDevices()
        }
    }

    func stop() {
        sessionQueue.async {
            self.desiredRunning = false
            guard self.session.isRunning else {
                self.notifyRunning(false)
                return
            }
            self.session.stopRunning()
            self.notifyRunning(false)
        }
    }

    func selectDevice(id: String?) {
        sessionQueue.async {
            self.reconfigure(preferredDeviceID: id)
            if self.desiredRunning {
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                self.notifyRunning(self.session.isRunning)
            }
        }
    }

    func stopImmediately() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func refreshDevices() {
        sessionQueue.async {
            self.notifyDevices()
            if let currentDeviceID = self.currentDeviceID,
               !Self.discoverDevices().contains(where: { $0.uniqueID == currentDeviceID }) {
                self.reconfigure(preferredDeviceID: nil)
                if self.desiredRunning {
                    self.session.startRunning()
                    self.notifyRunning(self.session.isRunning)
                }
            }
        }
    }

    static func discoverDevices() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        )
        var seen = Set<String>()
        return discovery.devices.filter { device in
            guard !seen.contains(device.uniqueID) else { return false }
            seen.insert(device.uniqueID)
            return true
        }
    }

    private func ensureConfigured(preferredDeviceID: String?) {
        let needsDeviceChange = preferredDeviceID != nil && preferredDeviceID != currentDeviceID
        if !outputsConfigured || currentInput == nil || needsDeviceChange {
            reconfigure(preferredDeviceID: preferredDeviceID)
        }
    }

    private func reconfigure(preferredDeviceID: String?) {
        let wasRunning = session.isRunning
        if wasRunning {
            session.stopRunning()
        }

        session.beginConfiguration()

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }

        let device = resolveDevice(preferredDeviceID: preferredDeviceID)
        if let device {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    throw CameraSetupError.cannotAddInput
                }
                session.addInput(input)
                currentInput = input
                currentDeviceID = device.uniqueID
                applyFormatAndFocus(to: device)
                logger.notice("Using camera \(device.localizedName, privacy: .public) (\(device.uniqueID, privacy: .public))")
            } catch {
                logger.error("Could not use camera: \(error.localizedDescription, privacy: .public)")
                currentDeviceID = nil
                reportError("Could not use the camera: \(error.localizedDescription)")
            }
        } else {
            currentDeviceID = nil
            reportError("No camera found.")
        }

        if !outputsConfigured {
            addOutputs()
        }

        session.commitConfiguration()
        configureOutputs()
        notifyDevices()

        if wasRunning, desiredRunning, currentInput != nil {
            session.startRunning()
            notifyRunning(session.isRunning)
        }
    }

    private func resolveDevice(preferredDeviceID: String?) -> AVCaptureDevice? {
        let devices = Self.discoverDevices()
        if let preferredDeviceID,
           let preferred = devices.first(where: { $0.uniqueID == preferredDeviceID }) {
            return preferred
        }
        if let systemDefault = AVCaptureDevice.default(for: .video) {
            return systemDefault
        }
        return devices.first
    }

    private func addOutputs() {
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        } else {
            logger.error("Could not add video data output")
            reportError("The camera output could not be created.")
        }

        if session.canAddOutput(metadataOutput) {
            metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
            session.addOutput(metadataOutput)
        }
        outputsConfigured = true
    }

    private func configureOutputs() {
        let available = Set(metadataOutput.availableMetadataObjectTypes)
        let supported = BarcodeFormats.metadataTypes.filter { available.contains($0) }
        if !supported.isEmpty {
            metadataOutput.metadataObjectTypes = supported
        }
    }

    private func applyFormatAndFocus(to device: AVCaptureDevice) {
        guard let format = Self.bestFormat(for: device) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.activeFormat = format
            if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30.0 }) {
                let duration = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
        } catch {
            logger.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        func dimensions(_ format: AVCaptureDevice.Format) -> CMVideoDimensions {
            CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        }
        func maxFPS(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        }

        let usable = device.formats.filter {
            let size = dimensions($0)
            return size.width >= 640 && size.height >= 480 && maxFPS($0) >= 29.5
        }
        guard !usable.isEmpty else { return device.formats.first }

        let capped = usable.filter { dimensions($0).width <= 1920 }
        let pool = capped.isEmpty ? usable : capped
        let wide = pool.filter {
            let size = dimensions($0)
            return abs(Double(size.width) / Double(size.height) - 16.0 / 9.0) < 0.1
        }
        let candidates = wide.isEmpty ? pool : wide

        return candidates.max {
            let lhs = dimensions($0)
            let rhs = dimensions($1)
            if lhs.width != rhs.width {
                return lhs.width < rhs.width
            }
            return maxFPS($0) < maxFPS($1)
        }
    }

    private func notifyDevices() {
        guard let currentDeviceID else {
            let devices = Self.discoverDevices().map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
            DispatchQueue.main.async { self.onDevicesChanged?(devices, nil) }
            return
        }
        let devices = Self.discoverDevices().map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
        DispatchQueue.main.async { self.onDevicesChanged?(devices, currentDeviceID) }
    }

    private func notifyRunning(_ running: Bool) {
        DispatchQueue.main.async { self.onRunningChanged?(running) }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { self.onError?(message) }
    }

    @objc private func deviceWasConnected() {
        sessionQueue.async { self.notifyDevices() }
    }

    @objc private func deviceWasDisconnected() {
        sessionQueue.async {
            self.notifyDevices()
            guard let currentDeviceID = self.currentDeviceID,
                  !Self.discoverDevices().contains(where: { $0.uniqueID == currentDeviceID }) else { return }
            self.reconfigure(preferredDeviceID: nil)
            if self.desiredRunning {
                self.session.startRunning()
                self.notifyRunning(self.session.isRunning)
            }
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
        logger.error("Capture session error: \(error.localizedDescription, privacy: .public)")
        reportError(error.localizedDescription)

        sessionQueue.asyncAfter(deadline: .now() + 1) {
            guard self.desiredRunning, self.retryCount < 3, !self.session.isRunning, self.currentInput != nil else { return }
            self.retryCount += 1
            self.logger.notice("Retrying capture session attempt \(self.retryCount, privacy: .public)")
            self.session.startRunning()
            self.notifyRunning(self.session.isRunning)
        }
    }
}

private enum CameraSetupError: LocalizedError {
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .cannotAddInput: return "The camera could not be added to the capture session."
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = visionRequest ?? makeVisionRequest()
        visionRequest = request

        var candidates: [ScanCandidate] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            candidates = (request.results ?? []).compactMap(Self.candidate(from:))
        } catch {
            logger.debug("Vision failed: \(error.localizedDescription, privacy: .public)")
        }

        // Metadata output is only a fallback: the two decoders disagree on some
        // payload conventions and mixing them would prevent the vote from converging.
        if candidates.isEmpty {
            let now = Date()
            metadataLock.lock()
            if now.timeIntervalSince(metadataTimestamp) < 0.15 {
                candidates = metadataCandidates
            }
            metadataLock.unlock()
        }

        onCandidates?(candidates)
    }

    private func makeVisionRequest() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision4
        request.symbologies = BarcodeFormats.visionSymbologies
        request.coalesceCompositeSymbologies = false
        return request
    }

    private static func candidate(from observation: VNBarcodeObservation) -> ScanCandidate? {
        guard let value = observation.payloadStringValue, !value.isEmpty else { return nil }
        let box = observation.boundingBox
        return ScanCandidate(
            value: value,
            symbology: SymbologyName.name(for: observation.symbology),
            confidence: observation.confidence,
            area: box.width * box.height,
            distanceFromCenter: hypot(box.midX - 0.5, box.midY - 0.5),
            source: .vision
        )
    }
}

extension CameraController: AVCaptureMetadataOutputObjectsDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let candidates: [ScanCandidate] = metadataObjects.compactMap { object in
            guard let barcode = object as? AVMetadataMachineReadableCodeObject,
                  BarcodeFormats.metadataTypes.contains(barcode.type),
                  let value = barcode.stringValue,
                  !value.isEmpty else { return nil }
            let box = barcode.bounds
            return ScanCandidate(
                value: value,
                symbology: SymbologyName.name(for: barcode.type),
                confidence: 1,
                area: box.width * box.height,
                distanceFromCenter: hypot(box.midX - 0.5, box.midY - 0.5),
                source: .metadata
            )
        }

        metadataLock.lock()
        metadataCandidates = candidates
        metadataTimestamp = Date()
        metadataLock.unlock()
    }
}
