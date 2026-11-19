import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)

if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.run()
} else {
    app.run()
}
