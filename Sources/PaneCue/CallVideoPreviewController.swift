import AppKit
@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import CoreGraphics
import OSLog
import PaneCueCore
@preconcurrency import ScreenCaptureKit
@preconcurrency import Vision

enum CallVideoPreviewError: LocalizedError {
    case screenRecordingPermissionRequired
    case noCallWindow
    case noBrowserWindow
    case captureFailed(source: String, details: String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "Screen Recording access is off. PaneCue will not ask again automatically; enable it in System Settings → Privacy & Security → Screen & System Audio Recording."
        case .noCallWindow:
            return "PaneCue could not find an open call window."
        case .noBrowserWindow:
            return "PaneCue could not find an open browser window. Open the video tab and try again."
        case let .captureFailed(source, details):
            return "PaneCue could not start the \(source) preview: \(details)"
        }
    }
}

private enum FloatingVideoSource {
    case call
    case browserVideo

    var panelSize: NSSize {
        switch self {
        case .call:
            return NSSize(width: 300, height: 180)
        case .browserVideo:
            return NSSize(width: 420, height: 236)
        }
    }

    var startingStatus: String {
        switch self {
        case .call:
            return "Starting call video…"
        case .browserVideo:
            return "Extracting browser video…"
        }
    }

    var sourceDescription: String {
        switch self {
        case .call:
            return "call video"
        case .browserVideo:
            return "browser video"
        }
    }
}

@MainActor
final class CallVideoPreviewController: NSObject {
    private let logger = Logger(
        subsystem: PaneCueIdentity.bundleIdentifier,
        category: "CallVideoPreview"
    )

    private let previewView: CallVideoPreviewView
    private let panel: NSPanel
    private let chromeVideoSession = ChromeVideoSessionController()
    private let screenRecordingRequestKey =
        "PaneCue.didRequestScreenRecordingPermission"
    private var stream: SCStream?
    private(set) var isCapturing = false
    private var activeSource: FloatingVideoSource?
    private var detectedBrowserCrop: CGRect?
    private var nativePictureInPictureMonitor:
        Task<Void, Never>?
    var onUserClose: (() -> Void)?
    private lazy var browserVideoDetector =
        BrowserVideoRectangleDetector { [weak self] rectangle in
            Task { @MainActor [weak self] in
                self?.applyDetectedBrowserCrop(rectangle)
            }
        }

    override init() {
        let size = NSSize(width: 300, height: 180)
        previewView = CallVideoPreviewView(
            frame: NSRect(origin: .zero, size: size)
        )
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.contentView = previewView
        previewView.autoresizingMask = [.width, .height]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.sharingType = .readOnly

        previewView.onTogglePlayback = { [weak self] in
            self?.toggleBrowserPlayback()
        }
        previewView.onSeek = { [weak self] seconds in
            self?.seekBrowserVideo(by: seconds)
        }
        previewView.onClose = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await self.stopCapture()
                self.onUserClose?()
            }
        }
    }

    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func startCallCapture() async throws -> String {
        try await startCapture(source: .call)
    }

    func startBrowserVideoCapture() async throws -> String {
        try await startCapture(source: .browserVideo)
    }

    private func startCapture(
        source: FloatingVideoSource
    ) async throws -> String {
        await stopCapture(hidePanel: false)
        activeSource = source
        detectedBrowserCrop = nil
        browserVideoDetector.reset()
        panel.setContentSize(source.panelSize)
        previewView.prepareForCapture()
        showPanel()
        previewView.showStatus(source.startingStatus)

        if !hasScreenRecordingPermission {
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: screenRecordingRequestKey) else {
                previewView.showStatus("Screen Recording access required")
                throw CallVideoPreviewError.screenRecordingPermissionRequired
            }

            defaults.set(true, forKey: screenRecordingRequestKey)
            let granted = CGRequestScreenCaptureAccess()
            guard granted else {
                previewView.showStatus("Screen Recording access required")
                throw CallVideoPreviewError.screenRecordingPermissionRequired
            }
        }

        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw CallVideoPreviewError.captureFailed(
                source: source.sourceDescription,
                details: error.localizedDescription
            )
        }

        let candidates = shareableContent.windows.filter { window in
            guard let application = window.owningApplication,
                  window.windowLayer == 0,
                  window.frame.width >= 200,
                  window.frame.height >= 140
            else {
                return false
            }

            let role = ApplicationRoleClassifier.role(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                windowTitle: window.title ?? ""
            )

            switch source {
            case .call:
                return role == .meeting
            case .browserVideo:
                return role == .browser
            }
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        guard let sourceWindow = preferredSourceWindow(
            from: candidates,
            source: source,
            frontmostPID: frontmostPID
        ) else {
            switch source {
            case .call:
                previewView.showStatus("Open a call window to start the preview")
                throw CallVideoPreviewError.noCallWindow
            case .browserVideo:
                previewView.showStatus("Open the browser video tab and try again")
                throw CallVideoPreviewError.noBrowserWindow
            }
        }

        if source == .browserVideo,
           sourceWindow.owningApplication?.bundleIdentifier
            .caseInsensitiveCompare("com.google.Chrome") == .orderedSame {
            do {
                try await chromeVideoSession.startNativePictureInPicture(
                    preferredWindowFrame: sourceWindow.frame
                )
                isCapturing = true
                panel.orderOut(nil)
                startNativePictureInPictureMonitoring()
                logger.info("Started native Chrome Picture in Picture")
                return "Browser video is floating · Google Chrome"
            } catch {
                chromeVideoSession.stop()
                throw error
            }
        }

        let filter = SCContentFilter(
            desktopIndependentWindow: sourceWindow
        )
        let configuration = SCStreamConfiguration()
        let captureSize = sourceWindow.frame.size
        configuration.width = min(max(Int(captureSize.width * 2), 640), 1_440)
        configuration.height = min(max(Int(captureSize.height * 2), 360), 1_080)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: 30
        )
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true

        configureCrop(
            for: sourceWindow,
            source: source
        )

        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )

        do {
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: .main
            )
            stream = newStream
            try await newStream.startCapture()
            isCapturing = true
            chromeVideoSession.restoreOriginalWindowFocus()
            showPanel()
        } catch {
            stream = nil
            isCapturing = false
            chromeVideoSession.stop()
            previewView.showStatus("\(source.sourceDescription.capitalized) unavailable")
            throw CallVideoPreviewError.captureFailed(
                source: source.sourceDescription,
                details: error.localizedDescription
            )
        }

        logger.info("Started a floating video capture")
        let applicationName = sourceWindow.owningApplication?.applicationName
            ?? "application"
        return "\(source.sourceDescription.capitalized) is floating · \(applicationName)"
    }

    func stopCapture(hidePanel: Bool = true) async {
        nativePictureInPictureMonitor?.cancel()
        nativePictureInPictureMonitor = nil

        if let stream {
            do {
                try await stream.stopCapture()
            } catch {
                logger.error("Could not stop floating video capture cleanly")
            }
        }

        stream = nil
        isCapturing = false
        activeSource = nil
        detectedBrowserCrop = nil
        browserVideoDetector.reset()
        chromeVideoSession.stop()
        previewView.clearVideo()
        previewView.hideBrowserControls()
        previewView.endCapture()

        if hidePanel {
            panel.orderOut(nil)
        }
    }

    private func startNativePictureInPictureMonitoring() {
        nativePictureInPictureMonitor?.cancel()
        nativePictureInPictureMonitor = Task {
            [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                let isActive = (
                    try? chromeVideoSession
                        .isNativePictureInPictureActive()
                ) ?? false
                guard !isActive else {
                    continue
                }

                nativePictureInPictureMonitor = nil
                await stopCapture()
                onUserClose?()
                return
            }
        }
    }

    private func showPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.maxX - size.width - 16,
                    y: visibleFrame.maxY - size.height - 16
                )
            )
        }

        panel.orderFrontRegardless()
        previewView.refreshPointerState()
    }

    private func sourcePriority(
        _ window: SCWindow,
        source: FloatingVideoSource,
        frontmostPID: pid_t?
    ) -> Double {
        let title = (window.title ?? "").lowercased()
        let application = window.owningApplication
        let area = Double(window.frame.width * window.frame.height)
        let frontmostBonus = application?.processID == frontmostPID
            ? 20_000_000_000.0
            : 0
        let onScreenBonus = window.isOnScreen ? 5_000_000_000.0 : 0

        let markers: [String]
        switch source {
        case .call:
            markers = ["meeting", "meet", "call", "facetime", "zoom"]
        case .browserVideo:
            markers = [
                "youtube",
                "vimeo",
                "twitch",
                "netflix",
                "prime video",
                "disney+",
                "video",
                "player",
                "webinar",
                "coursera",
                "udemy"
            ]
        }

        let titleBonus = markers.contains(where: title.contains)
            ? 10_000_000_000.0
            : 0
        return frontmostBonus + onScreenBonus + titleBonus + area
    }

    private func preferredSourceWindow(
        from candidates: [SCWindow],
        source: FloatingVideoSource,
        frontmostPID: pid_t?
    ) -> SCWindow? {
        let orderedWindowIDs = frontToBackWindowIDs()
        let ranks = Dictionary(
            uniqueKeysWithValues: orderedWindowIDs.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let visibleCandidates = candidates.filter(\.isOnScreen)
        let rankedCandidates = visibleCandidates.isEmpty
            ? candidates
            : visibleCandidates

        if let topmost = rankedCandidates.min(by: { left, right in
            let leftRank = ranks[left.windowID] ?? Int.max
            let rightRank = ranks[right.windowID] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return sourcePriority(
                left,
                source: source,
                frontmostPID: frontmostPID
            ) > sourcePriority(
                right,
                source: source,
                frontmostPID: frontmostPID
            )
        }), ranks[topmost.windowID] != nil {
            return topmost
        }

        return candidates.max(by: {
            sourcePriority(
                $0,
                source: source,
                frontmostPID: frontmostPID
            ) < sourcePriority(
                $1,
                source: source,
                frontmostPID: frontmostPID
            )
        })
    }

    private func frontToBackWindowIDs() -> [CGWindowID] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]]
        else {
            return []
        }

        return windowInfo.compactMap { entry in
            guard let value = entry[kCGWindowNumber] as? NSNumber else {
                return nil
            }
            return CGWindowID(value.uint32Value)
        }
    }

    private func configureCrop(
        for window: SCWindow,
        source: FloatingVideoSource
    ) {
        switch source {
        case .call:
            let bundleIdentifier = window.owningApplication?
                .bundleIdentifier.lowercased()
            if bundleIdentifier == "com.apple.facetime" {
                previewView.setFaceTimeCrop(
                    windowAspectRatio: window.frame.width / window.frame.height
                )
            } else {
                previewView.setFullFrameCrop()
            }
        case .browserVideo:
            previewView.beginBrowserPlayerSearch()
            previewView.hideBrowserControls()
        }
    }

    private func applyDetectedBrowserCrop(_ rectangle: CGRect) {
        guard activeSource == .browserVideo else {
            return
        }

        let smoothed: CGRect
        if let previous = detectedBrowserCrop {
            let oldWeight: CGFloat = 0.72
            let newWeight = 1 - oldWeight
            smoothed = CGRect(
                x: previous.origin.x * oldWeight
                    + rectangle.origin.x * newWeight,
                y: previous.origin.y * oldWeight
                    + rectangle.origin.y * newWeight,
                width: previous.width * oldWeight
                    + rectangle.width * newWeight,
                height: previous.height * oldWeight
                    + rectangle.height * newWeight
            )
        } else {
            smoothed = rectangle
        }

        detectedBrowserCrop = smoothed
        previewView.setBrowserPlayerCrop(smoothed)
    }

    private func toggleBrowserPlayback() {
        do {
            let paused = try chromeVideoSession.togglePlayback()
            previewView.setPlaybackPaused(paused)
        } catch {
            NSSound.beep()
            logger.error("Could not toggle browser video playback")
        }
    }

    private func seekBrowserVideo(by seconds: Double) {
        do {
            try chromeVideoSession.seek(by: seconds)
        } catch {
            NSSound.beep()
            logger.error("Could not seek browser video")
        }
    }
}

extension CallVideoPreviewController: @preconcurrency SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil
        else {
            return
        }

        previewView.enqueue(sampleBuffer)

        if activeSource == .browserVideo,
           let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            browserVideoDetector.analyze(imageBuffer)
        }
    }
}

extension CallVideoPreviewController: SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: any Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            logger.error("Floating video capture stopped unexpectedly")
            previewView.showStatus("Video capture stopped")
            self.stream = nil
            isCapturing = false
        }
    }
}

@MainActor
final class CallVideoPreviewView: NSView {
    private let videoLayer = AVSampleBufferDisplayLayer()
    private let statusLabel = NSTextField(labelWithString: "")
    private let controlsView = NSVisualEffectView()
    private let rewindButton = NSButton(
        title: "−10",
        target: nil,
        action: nil
    )
    private let playPauseButton = NSButton(
        image: NSImage(
            systemSymbolName: "pause.fill",
            accessibilityDescription: "Pause"
        ) ?? NSImage(),
        target: nil,
        action: nil
    )
    private let forwardButton = NSButton(
        title: "+10",
        target: nil,
        action: nil
    )
    private let closeButton = NSButton(
        image: NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close Floating Video"
        ) ?? NSImage(),
        target: nil,
        action: nil
    )
    private let controlsStack = NSStackView()
    private var waitsForBrowserPlayer = false
    private var browserControlsAvailable = false
    private var closeControlAvailable = false
    private var isPointerInside = false
    private var pointerTrackingArea: NSTrackingArea?
    private var pointerPollTimer: Timer?

    var onTogglePlayback: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        videoLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(videoLayer)

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        addSubview(statusLabel)

        controlsView.material = .hudWindow
        controlsView.blendingMode = .withinWindow
        controlsView.state = .active
        controlsView.wantsLayer = true
        controlsView.layer?.cornerRadius = 18
        controlsView.layer?.masksToBounds = true
        controlsView.isHidden = true
        addSubview(controlsView)

        configureControlButton(rewindButton)
        configureControlButton(playPauseButton)
        configureControlButton(forwardButton)
        configureControlButton(closeButton)
        rewindButton.target = self
        rewindButton.action = #selector(rewindVideo)
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayback)
        forwardButton.target = self
        forwardButton.action = #selector(forwardVideo)
        closeButton.target = self
        closeButton.action = #selector(closePreview)
        closeButton.toolTip = "Close Floating Video"
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.68).cgColor
        closeButton.layer?.cornerRadius = 13
        closeButton.isHidden = true
        addSubview(closeButton)

        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.distribution = .fillEqually
        controlsStack.spacing = 2
        controlsStack.addArrangedSubview(rewindButton)
        controlsStack.addArrangedSubview(playPauseButton)
        controlsStack.addArrangedSubview(forwardButton)
        controlsView.addSubview(controlsStack)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        videoLayer.frame = bounds
        statusLabel.frame = bounds.insetBy(dx: 24, dy: 24)
        let controlsWidth: CGFloat = 154
        controlsView.frame = NSRect(
            x: (bounds.width - controlsWidth) / 2,
            y: 10,
            width: controlsWidth,
            height: 36
        )
        controlsStack.frame = controlsView.bounds.insetBy(
            dx: 5,
            dy: 3
        )
        closeButton.frame = NSRect(
            x: bounds.maxX - 36,
            y: bounds.maxY - 36,
            width: 26,
            height: 26
        )
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateControlVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateControlVisibility()
    }

    override func mouseMoved(with event: NSEvent) {
        refreshPointerState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func refreshPointerState() {
        guard let window else {
            isPointerInside = false
            updateControlVisibility()
            return
        }

        let pointInWindow = window.convertPoint(
            fromScreen: NSEvent.mouseLocation
        )
        let localPoint = convert(pointInWindow, from: nil)
        isPointerInside = bounds.contains(localPoint)
        updateControlVisibility()
    }

    func prepareForCapture() {
        closeControlAvailable = true
        browserControlsAvailable = false
        isPointerInside = false
        startPointerPolling()
        updateControlVisibility()
    }

    func endCapture() {
        pointerPollTimer?.invalidate()
        pointerPollTimer = nil
        closeControlAvailable = false
        browserControlsAvailable = false
        isPointerInside = false
        updateControlVisibility()
    }

    func setFaceTimeCrop(windowAspectRatio: CGFloat) {
        videoLayer.contentsRect = windowAspectRatio > 1.3
            ? CGRect(x: 0.32, y: 0, width: 0.68, height: 1)
            : CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func setBrowserContentCrop(windowHeight: CGFloat) {
        let estimatedToolbarHeight = min(max(windowHeight * 0.1, 72), 110)
        let contentFraction = max(
            (windowHeight - estimatedToolbarHeight) / windowHeight,
            0.5
        )
        videoLayer.contentsRect = CGRect(
            x: 0,
            y: 0,
            width: 1,
            height: contentFraction
        )
    }

    func setBrowserPlayerCrop(_ rectangle: CGRect) {
        let padding: CGFloat = 0.008
        let expanded = rectangle.insetBy(
            dx: -padding,
            dy: -padding
        )
        videoLayer.contentsRect = expanded.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        waitsForBrowserPlayer = false
        videoLayer.isHidden = false
        statusLabel.isHidden = true
    }

    func beginBrowserPlayerSearch() {
        waitsForBrowserPlayer = true
        videoLayer.isHidden = true
        showStatus("Finding the video player…")
    }

    func showBrowserControls(paused: Bool) {
        setPlaybackPaused(paused)
        browserControlsAvailable = true
        updateControlVisibility()
    }

    func hideBrowserControls() {
        browserControlsAvailable = false
        updateControlVisibility()
    }

    func setPlaybackPaused(_ paused: Bool) {
        let symbol = paused ? "play.fill" : "pause.fill"
        let description = paused ? "Play" : "Pause"
        playPauseButton.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )
        playPauseButton.toolTip = description
    }

    func setFullFrameCrop() {
        videoLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        waitsForBrowserPlayer = false
        videoLayer.isHidden = false
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if !waitsForBrowserPlayer {
            statusLabel.isHidden = true
            videoLayer.isHidden = false
        }
        videoLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    func showStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = false
    }

    func clearVideo() {
        videoLayer.flushAndRemoveImage()
        waitsForBrowserPlayer = false
        videoLayer.isHidden = false
        statusLabel.isHidden = false
    }

    private func configureControlButton(_ button: NSButton) {
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .white
        button.focusRingType = .none
    }

    private func updateControlVisibility() {
        controlsView.isHidden = !(
            isPointerInside && browserControlsAvailable
        )
        closeButton.isHidden = !(
            isPointerInside && closeControlAvailable
        )
    }

    private func startPointerPolling() {
        pointerPollTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(pollPointerLocation),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pointerPollTimer = timer
    }

    @objc
    private func pollPointerLocation() {
        refreshPointerState()
    }

    @objc
    private func togglePlayback() {
        onTogglePlayback?()
    }

    @objc
    private func rewindVideo() {
        onSeek?(-10)
    }

    @objc
    private func forwardVideo() {
        onSeek?(10)
    }

    @objc
    private func closePreview() {
        onClose?()
    }
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

private final class BrowserVideoRectangleDetector: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: PaneCueIdentity.subsystem("browser-video-detector"),
        qos: .userInitiated
    )
    private let lock = NSLock()
    private let didDetect: @Sendable (CGRect) -> Void
    private var isProcessing = false
    private var lastAnalysis = Date.distantPast

    init(didDetect: @escaping @Sendable (CGRect) -> Void) {
        self.didDetect = didDetect
    }

    func reset() {
        lock.withLock {
            isProcessing = false
            lastAnalysis = .distantPast
        }
    }

    func analyze(_ pixelBuffer: CVPixelBuffer) {
        let shouldAnalyze = lock.withLock {
            guard !isProcessing,
                  Date().timeIntervalSince(lastAnalysis) >= 0.9
            else {
                return false
            }

            isProcessing = true
            lastAnalysis = Date()
            return true
        }

        guard shouldAnalyze else {
            return
        }

        let sendableBuffer = SendablePixelBuffer(value: pixelBuffer)
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let rectangle = Self.detectPlayer(
                in: sendableBuffer.value
            )
            lock.withLock {
                isProcessing = false
            }

            if let rectangle {
                didDetect(rectangle)
            }
        }
    }

    private static func detectPlayer(
        in pixelBuffer: CVPixelBuffer
    ) -> CGRect? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 16
        request.minimumSize = 0.16
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1
        request.minimumConfidence = 0.45
        request.quadratureTolerance = 18

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let pixelWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let pixelHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard pixelWidth > 0, pixelHeight > 0,
              let observations = request.results
        else {
            return nil
        }

        return observations
            .compactMap { observation -> (CGRect, Double)? in
                let rectangle = observation.boundingBox
                let area = rectangle.width * rectangle.height

                guard area >= 0.12, area <= 0.9,
                      rectangle.width >= 0.28,
                      rectangle.height >= 0.18
                else {
                    return nil
                }

                let aspectRatio = (
                    rectangle.width * pixelWidth
                ) / (
                    rectangle.height * pixelHeight
                )
                guard aspectRatio >= 1.2, aspectRatio <= 2.5 else {
                    return nil
                }

                let targetAspect: CGFloat = 16 / 9
                let aspectDistance = abs(
                    log(aspectRatio / targetAspect)
                )
                let aspectScore = max(
                    1 - Double(aspectDistance),
                    0
                )

                let center = CGPoint(
                    x: rectangle.midX,
                    y: rectangle.midY
                )
                let centerDistance = hypot(
                    center.x - 0.5,
                    center.y - 0.5
                )
                let centerScore = max(
                    1 - Double(centerDistance),
                    0
                )
                let score = Double(area) * 2.2
                    + aspectScore * 1.4
                    + centerScore * 0.35
                    + Double(observation.confidence) * 0.25

                return (rectangle, score)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
