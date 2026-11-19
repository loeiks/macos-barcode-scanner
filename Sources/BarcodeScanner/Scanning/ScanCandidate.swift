import Foundation
import AVFoundation
import Vision

struct ScanCandidate {
    enum Source {
        case metadata
        case vision
    }

    let value: String
    let symbology: String
    let confidence: Float
    let area: CGFloat
    let distanceFromCenter: CGFloat
    let source: Source
}

struct ScanResult {
    let value: String
    let symbology: String
}

enum SymbologyName {
    static func name(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code39, .code39Mod43: return "Code 39"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .interleaved2of5: return "Interleaved 2 of 5"
        case .itf14: return "ITF-14"
        case .codabar: return "Codabar"
        case .gs1DataBar: return "GS1 DataBar"
        case .gs1DataBarExpanded: return "GS1 DataBar Expanded"
        case .gs1DataBarLimited: return "GS1 DataBar Limited"
        default: return "Barcode"
        }
    }

    static func name(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: return "Code 39"
        case .code93, .code93i: return "Code 93"
        case .code128: return "Code 128"
        case .i2of5, .i2of5Checksum: return "Interleaved 2 of 5"
        case .itf14: return "ITF-14"
        case .codabar: return "Codabar"
        case .gs1DataBar: return "GS1 DataBar"
        case .gs1DataBarExpanded: return "GS1 DataBar Expanded"
        case .gs1DataBarLimited: return "GS1 DataBar Limited"
        default: return "Barcode"
        }
    }
}

enum BarcodeFormats {
    static let metadataTypes: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code39, .code39Mod43, .code93, .code128,
        .interleaved2of5, .itf14, .codabar,
        .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
    ]

    static let visionSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce,
        .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
        .code93, .code128, .i2of5, .i2of5Checksum, .itf14, .codabar,
        .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
    ]
}
