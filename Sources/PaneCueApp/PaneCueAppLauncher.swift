import AppKit

@MainActor
public func runPaneCueApplication() {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()

    application.delegate = appDelegate
    application.run()
}
