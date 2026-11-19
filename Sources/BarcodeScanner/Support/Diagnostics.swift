import AVFoundation
import Foundation

enum Diagnostics {
    private static var camera: CameraController?

    static func run() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("camera authorization: \(status.name)")

        let devices = CameraController.discoverDevices()
        print("cameras: \(devices.count)")
        for device in devices {
            print("- \(device.localizedName) [\(device.uniqueID)] continuity=\(device.isContinuityCamera)")
            let formats = device.formats.compactMap { format -> String? in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let fps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return "\(size.width)x\(size.height)@\(Int(fps))"
            }
            print("  formats: \(Set(formats).sorted().joined(separator: ", "))")
        }

        guard CommandLine.arguments.contains("--capture") else {
            exit(0)
        }

        switch status {
        case .authorized:
            runCaptureTest()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        print("camera access denied")
                        exit(1)
                    }
                    runCaptureTest()
                }
            }
        default:
            print("camera access denied")
            exit(1)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(10))
        print("capture test finished")
        exit(0)
    }

    private static func runCaptureTest() {
        let camera = CameraController()
        self.camera = camera
        let lock = NSLock()
        var detected = Set<String>()

        camera.onCandidates = { candidates in
            guard !candidates.isEmpty else { return }
            lock.lock()
            candidates.forEach { detected.insert("\($0.symbology): \($0.value)") }
            lock.unlock()
        }
        camera.onRunningChanged = { running in
            print("session running: \(running)")
        }
        camera.onError = { message in
            print("camera error: \(message)")
        }

        camera.start(preferredDeviceID: nil)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            lock.lock()
            let current = detected
            detected.removeAll()
            lock.unlock()
            if !current.isEmpty {
                print("detected: \(current.sorted().joined(separator: " | "))")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

private extension AVAuthorizationStatus {
    var name: String {
        switch self {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}
