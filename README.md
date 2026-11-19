# Barcode Scanner

A menu bar barcode scanner for macOS. It reads product and shipping barcodes from any camera the Mac can use, including the built-in FaceTime camera, USB cameras and a connected iPhone (Continuity Camera).

## Requirements

- macOS 14 or newer
- A camera (built-in, USB, or iPhone via Continuity Camera)

## Build and install

```bash
./scripts/build-app.sh
open "dist/Barcode Scanner.app"
```

To keep it around, move the app to Applications first:

```bash
cp -R "dist/Barcode Scanner.app" /Applications/
open /Applications/"Barcode Scanner.app"
```

The app has no Dock icon. It lives in the menu bar.

## First run

1. macOS asks for camera access — allow it.
2. Paste modes also need Accessibility access. Open the popover and click **Accessibility needed for paste** to grant it. This is only used to send ⌘V and Return to the app that was focused when the code was scanned.

## Usage

- Click the menu bar icon to open the popover.
- **⌥⌘B** toggles between scanning and sleeping.
- When no barcode has been scanned for a while, the app stops the camera. Click the icon or press the shortcut to wake it.
- Scans always copy the value to the clipboard and play a sound.

### Output modes

| Mode | Behaviour |
|---|---|
| Copy | Copies the value only. |
| Paste | Copies and sends ⌘V to the focused app. |
| Paste + Enter | Copies, sends ⌘V, then Return. |

Copy + Paste is the default.

A barcode is emitted only after it has been read in two consecutive frames. After a scan, the same value cannot be emitted again until it leaves the camera view. This makes accidental double pastes and single-frame misreads very unlikely without adding noticeable latency.

## Supported symbologies

Linear barcodes only:

- EAN-13, EAN-8, UPC-E (UPC-A values are returned in their 13-digit EAN-13 form)
- Code 39, Code 93, Code 128, GS1-128
- Interleaved 2 of 5, ITF-14
- Codabar
- GS1 DataBar, GS1 DataBar Limited, GS1 DataBar Expanded

Values are returned exactly as decoded. Leading zeros, check digits and GS1 separators are not stripped or rewritten. QR codes and all other 2D codes are intentionally ignored.

## How it works

The app runs two native decoders on the same camera frames:

- `AVCaptureMetadataOutput`, the capture pipeline's low-latency barcode detector.
- Vision's `VNDetectBarcodesRequest` (revision 4), which is robust on small, rotated and slightly blurred codes.

The camera runs at 1920×1080 and continuous autofocus, exposed at the centre of the frame. Results from both decoders are merged, then a two-frame consensus filter decides when a barcode is real. The frame rate is capped at 30 fps: a longer exposure gives cleaner frames in normal indoor light, and 30 fps is already fast enough for two-frame confirmation in about 70 ms.

Benchmarks against ZXing-C++ on generated product/shipping barcodes (small sizes, rotation, blur, noise) showed Vision decoding more codes, including 45° rotated barcodes that ZXing could not read, so the app uses the native pipeline without third-party dependencies.

## Development

```
Sources/BarcodeScanner/
  App/          menu bar item, popover, app model
  Camera/       capture session, device/format selection, Vision pipeline
  Scanning/     symbology names, candidate model, stability filter
  Output/       clipboard, synthetic paste, sound, global hotkey
  Settings/     persisted preferences
  Support/      diagnostics
Resources/      Info.plist and app icon
scripts/        app bundle build script
```

The app is built with Swift Package Manager using the command line tools. No Xcode project is required.

### Diagnostics

```bash
"dist/Barcode Scanner.app/Contents/MacOS/BarcodeScanner" --diagnose
```

Lists cameras and their formats. Add `--capture` to start the camera for a few seconds and print any detected barcodes.

### Signing

The build script signs the bundle ad-hoc by default. Ad-hoc signatures change on every rebuild, which makes macOS forget camera and Accessibility grants. For development, create a local self-signed identity once:

```bash
./scripts/dev-cert.sh
```

The build script picks it up automatically and the permissions survive rebuilds. Set `CODESIGN_IDENTITY` to use a Developer ID for distribution:

```bash
CODESIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
```

## Notes

- The camera runs only while the app is awake; sleeping stops the capture session and releases the camera.
- `Launch at login` uses `SMAppService`, so the app must be in a stable location such as `/Applications`.
- Multiple displays and Spaces are fine; the popover is transient and the scanner works from any app.
