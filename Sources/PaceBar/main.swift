import AppKit

// A menu bar agent: no Dock icon (LSUIElement in Info.plist; set here too for `swift run`).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
