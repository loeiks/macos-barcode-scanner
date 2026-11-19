// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarcodeScanner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BarcodeScanner",
            path: "Sources/BarcodeScanner"
        )
    ]
)
