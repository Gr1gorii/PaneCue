import AppKit

@MainActor
public func runPaneCueApplication() {
    runPaneCueApplication(
        featureProvider: StablePaneCueFeatureProvider()
    )
}

@MainActor
public func runPaneCueApplication(
    featureProvider: any PaneCueFeatureProvider
) {
    let application = NSApplication.shared
    let appDelegate = AppDelegate(featureProvider: featureProvider)

    application.delegate = appDelegate
    application.run()
}
