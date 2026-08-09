import AppKit

enum ChromeVideoSessionError: LocalizedError {
    case chromeUnavailable
    case noWindow
    case noVideo
    case javascriptAccessRequired
    case automationAccessRequired
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .chromeUnavailable:
            return "Google Chrome is not running."
        case .noWindow:
            return "Open the Chrome tab that contains the video, then try again."
        case .noVideo:
            return "PaneCue could not find a visible video player in the active Chrome tab."
        case .javascriptAccessRequired:
            return "Chrome blocked access to the video player. In Chrome, enable View → Developer → Allow JavaScript from Apple Events, then try again. PaneCue uses it only for the selected video’s bounds, pause, and ±10 second controls."
        case .automationAccessRequired:
            return "macOS blocked PaneCue from controlling the selected Chrome video. Enable PaneCue → Google Chrome in System Settings → Privacy & Security → Automation, then try again."
        case let .automationFailed(details):
            return "PaneCue could not prepare the Chrome video tab: \(details)"
        }
    }
}

private struct ChromeVideoPlayerState: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

@MainActor
final class ChromeVideoSessionController {
    private struct ActiveSession {
        let originalWindowID: CGWindowID
        let originalTabID: String
        var placeholderTabID: String?
    }

    private struct SourceReference {
        let windowID: CGWindowID
        let tabID: String
    }

    private var session: ActiveSession?

    var isActive: Bool {
        session != nil
    }

    func restoreOriginalWindowFocus() {
        guard let session else {
            return
        }

        _ = try? runDescriptor(
            """
            tell application "Google Chrome"
                try
                    set index of window id \(session.originalWindowID) to 1
                end try
            end tell
            """
        )
    }

    func startNativePictureInPicture(
        preferredWindowFrame: CGRect? = nil
    ) async throws {
        let source = try sourceReference(
            preferredWindowFrame: preferredWindowFrame
        )
        let setupResult = try executeJavaScript(
            Self.installPictureInPictureJavaScript,
            windowID: source.windowID,
            tabID: source.tabID
        )
        guard setupResult == "ready" else {
            throw ChromeVideoSessionError.noVideo
        }

        session = ActiveSession(
            originalWindowID: source.windowID,
            originalTabID: source.tabID,
            placeholderTabID: nil
        )

        do {
            try backgroundOriginalTab()
            for _ in 0..<8 {
                if try isNativePictureInPictureActive() {
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }

            restoreOriginalWindow(session!)
            guard let preferredWindowFrame else {
                session = nil
                throw ChromeVideoSessionError.automationFailed(
                    "Chrome needs one click on the video before Picture in Picture can open."
                )
            }
            try await requestNativePictureInPictureWithTrustedClick(
                sourceFrame: preferredWindowFrame
            )
            try backgroundOriginalTab()
        } catch {
            if let session {
                restoreOriginalWindow(session)
            }
            self.session = nil
            throw error
        }
    }

    private func backgroundOriginalTab() throws {
        guard var session else {
            throw ChromeVideoSessionError.noWindow
        }

        let descriptor = try runDescriptor(
            """
            tell application "Google Chrome"
                set originalWindow to window id \(session.originalWindowID)
                set sourceTabIndex to 1
                repeat with tabIndex from 1 to (count of tabs of originalWindow)
                    if (id of tab tabIndex of originalWindow as text) is \(quoted(session.originalTabID)) then
                        set sourceTabIndex to tabIndex
                        exit repeat
                    end if
                end repeat
                set placeholderID to ""
                if (count of tabs of originalWindow) is 1 then
                    set placeholderTab to make new tab at end of tabs of originalWindow with properties {URL:"chrome://newtab/"}
                    set placeholderID to id of placeholderTab as text
                    set active tab index of originalWindow to 2
                else if sourceTabIndex is 1 then
                    set active tab index of originalWindow to 2
                else
                    set active tab index of originalWindow to 1
                end if
                set index of originalWindow to 1
                return placeholderID
            end tell
            """
        )
        let placeholderID = descriptor.stringValue ?? ""
        session.placeholderTabID = placeholderID.isEmpty
            ? nil
            : placeholderID
        self.session = session
    }

    func togglePlayback() throws -> Bool {
        guard let session else {
            throw ChromeVideoSessionError.noWindow
        }

        let result = try executeJavaScript(
            Self.togglePlaybackJavaScript,
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )
        return result == "true"
    }

    func seek(by seconds: Double) throws {
        guard let session else {
            throw ChromeVideoSessionError.noWindow
        }

        let boundedSeconds = min(max(seconds, -3_600), 3_600)
        let script = Self.seekJavaScript.replacingOccurrences(
            of: "__SECONDS__",
            with: String(boundedSeconds)
        )
        _ = try executeJavaScript(
            script,
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )
    }

    func stop() {
        guard let session else {
            return
        }
        self.session = nil

        _ = try? executeJavaScript(
            Self.exitPictureInPictureJavaScript,
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )

        restoreOriginalWindow(session)
    }

    func isNativePictureInPictureActive() throws -> Bool {
        guard let session else {
            return false
        }
        return try executeJavaScript(
            "String(Boolean(document.pictureInPictureElement))",
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        ) == "true"
    }

    private func requestNativePictureInPictureWithTrustedClick(
        sourceFrame: CGRect
    ) async throws {
        guard let session else {
            throw ChromeVideoSessionError.noWindow
        }
        guard AXIsProcessTrusted() else {
            throw ChromeVideoSessionError.automationAccessRequired
        }

        let player = try playerState(
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )
        let triggerResult = try executeJavaScript(
            Self.installPictureInPictureTriggerJavaScript,
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )
        guard triggerResult == "ready" else {
            throw ChromeVideoSessionError.noVideo
        }

        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.google.Chrome"
        ).first?.activate(options: [.activateAllWindows])
        try await Task.sleep(for: .milliseconds(180))

        let clickPoint = CGPoint(
            x: sourceFrame.minX + player.x + player.width / 2,
            y: sourceFrame.minY + player.y + player.height / 2
        )
        postMouseEvent(.mouseMoved, at: clickPoint)
        try await Task.sleep(for: .milliseconds(40))
        postMouseEvent(.leftMouseDown, at: clickPoint)
        postMouseEvent(.leftMouseUp, at: clickPoint)

        for _ in 0..<24 {
            if try isNativePictureInPictureActive() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        _ = try? executeJavaScript(
            Self.removePictureInPictureTriggerJavaScript,
            windowID: session.originalWindowID,
            tabID: session.originalTabID
        )
        throw ChromeVideoSessionError.automationFailed(
            "Chrome did not accept the Picture in Picture action."
        )
    }

    private func postMouseEvent(
        _ type: CGEventType,
        at point: CGPoint
    ) {
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func sourceReference(
        preferredWindowFrame: CGRect?
    ) throws -> SourceReference {
        let sourceWindowSelection: String
        if let preferredWindowFrame,
           let preferredWindowID = try? chromeWindowID(
               matching: preferredWindowFrame
           ) {
            sourceWindowSelection =
                "set sourceWindow to window id \(preferredWindowID)"
        } else {
            sourceWindowSelection = "set sourceWindow to front window"
        }

        let descriptor = try runDescriptor(
            """
            tell application "Google Chrome"
                if (count of windows) is 0 then error "NO_CHROME_WINDOW"
                \(sourceWindowSelection)
                set sourceTab to active tab of sourceWindow
                return {id of sourceWindow as text, id of sourceTab as text}
            end tell
            """
        )

        guard descriptor.numberOfItems == 2,
              let windowIDString = descriptor.atIndex(1)?.stringValue,
              let windowID = CGWindowID(windowIDString),
              let tabID = descriptor.atIndex(2)?.stringValue
        else {
            throw ChromeVideoSessionError.noWindow
        }
        return SourceReference(
            windowID: windowID,
            tabID: tabID
        )
    }

    private func chromeWindowID(
        matching preferredFrame: CGRect
    ) throws -> CGWindowID? {
        let descriptor = try runDescriptor(
            """
            tell application "Google Chrome"
                set windowDescriptions to {}
                repeat with candidateWindow in windows
                    set candidateBounds to bounds of candidateWindow
                    set end of windowDescriptions to {id of candidateWindow as text, item 1 of candidateBounds, item 2 of candidateBounds, item 3 of candidateBounds, item 4 of candidateBounds}
                end repeat
                return windowDescriptions
            end tell
            """
        )

        var bestMatch: (id: CGWindowID, distance: CGFloat)?
        guard descriptor.numberOfItems > 0 else {
            return nil
        }
        for index in 1...descriptor.numberOfItems {
            guard let windowDescriptor = descriptor.atIndex(index),
                  windowDescriptor.numberOfItems == 5,
                  let idString = windowDescriptor.atIndex(1)?.stringValue,
                  let windowID = CGWindowID(idString)
            else {
                continue
            }

            let left = CGFloat(
                windowDescriptor.atIndex(2)?.int32Value ?? 0
            )
            let top = CGFloat(
                windowDescriptor.atIndex(3)?.int32Value ?? 0
            )
            let right = CGFloat(
                windowDescriptor.atIndex(4)?.int32Value ?? 0
            )
            let bottom = CGFloat(
                windowDescriptor.atIndex(5)?.int32Value ?? 0
            )
            let candidateFrame = CGRect(
                x: left,
                y: top,
                width: right - left,
                height: bottom - top
            )
            let distance =
                abs(candidateFrame.minX - preferredFrame.minX)
                + abs(candidateFrame.minY - preferredFrame.minY)
                + abs(candidateFrame.width - preferredFrame.width)
                + abs(candidateFrame.height - preferredFrame.height)

            if bestMatch.map({ distance < $0.distance }) ?? true {
                bestMatch = (windowID, distance)
            }
        }
        return bestMatch?.id
    }

    private func restoreOriginalWindow(
        _ session: ActiveSession
    ) {
        _ = try? runDescriptor(
            """
            tell application "Google Chrome"
                try
                    set originalWindow to window id \(session.originalWindowID)
                    if \(quoted(session.placeholderTabID ?? "")) is not "" then
                        repeat with placeholderTab in tabs of originalWindow
                            if (id of placeholderTab as text) is \(quoted(session.placeholderTabID ?? "")) then
                                if URL of placeholderTab starts with "chrome://newtab" then
                                    close placeholderTab
                                end if
                                exit repeat
                            end if
                        end repeat
                    end if
                    set sourceTabIndex to 0
                    repeat with tabIndex from 1 to (count of tabs of originalWindow)
                        if (id of tab tabIndex of originalWindow as text) is \(quoted(session.originalTabID)) then
                            set sourceTabIndex to tabIndex
                            exit repeat
                        end if
                    end repeat
                    if sourceTabIndex is greater than 0 then
                        set active tab index of originalWindow to sourceTabIndex
                    end if
                    set minimized of originalWindow to false
                    set index of originalWindow to 1
                end try
            end tell
            """
        )
    }

    private func playerState(
        windowID: CGWindowID,
        tabID: String?
    ) throws -> ChromeVideoPlayerState {
        let json = try executeJavaScript(
            Self.playerStateJavaScript,
            windowID: windowID,
            tabID: tabID
        )
        guard let data = json.data(using: .utf8) else {
            throw ChromeVideoSessionError.noVideo
        }

        if let payload = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any],
           payload["error"] as? String == "no_video" {
            throw ChromeVideoSessionError.noVideo
        }

        guard let state = try? JSONDecoder().decode(
            ChromeVideoPlayerState.self,
            from: data
        ) else {
            throw ChromeVideoSessionError.noVideo
        }
        return state
    }

    private func executeJavaScript(
        _ javascript: String,
        windowID: CGWindowID,
        tabID: String?
    ) throws -> String {
        let tabSelection: String
        if let tabID {
            tabSelection =
                """
                set targetTab to active tab of targetWindow
                repeat with candidateTab in tabs of targetWindow
                    if (id of candidateTab as text) is \(quoted(tabID)) then
                        set targetTab to candidateTab
                        exit repeat
                    end if
                end repeat
                """
        } else {
            tabSelection = "set targetTab to active tab of targetWindow"
        }

        let descriptor: NSAppleEventDescriptor
        do {
            descriptor = try runDescriptor(
                """
                tell application "Google Chrome"
                    set targetWindow to window id \(windowID)
                    \(tabSelection)
                    return execute targetTab javascript \(quoted(javascript))
                end tell
                """
            )
        } catch let error as ChromeVideoSessionError {
            if error.localizedDescription.localizedCaseInsensitiveContains(
                "javascript"
            ) {
                throw ChromeVideoSessionError.javascriptAccessRequired
            }
            throw error
        }
        return descriptor.stringValue ?? ""
    }

    private func runDescriptor(
        _ source: String
    ) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw ChromeVideoSessionError.automationFailed(
                "The browser command could not be created."
            )
        }

        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        if let details {
            let message = (
                details[NSAppleScript.errorMessage] as? String
            ) ?? "Unknown browser automation error."
            let errorNumber = details[
                NSAppleScript.errorNumber
            ] as? Int

            if errorNumber == -1_743
                || message.localizedCaseInsensitiveContains(
                    "not authorized to send apple events"
                ) {
                throw ChromeVideoSessionError.automationAccessRequired
            }
            if message.localizedCaseInsensitiveContains("javascript") {
                throw ChromeVideoSessionError.javascriptAccessRequired
            }
            if message.contains("NO_CHROME_WINDOW") {
                throw ChromeVideoSessionError.noWindow
            }
            throw ChromeVideoSessionError.automationFailed(message)
        }
        return result
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static let largestVideoExpression =
        """
        document.querySelector('video.html5-main-video')||[...document.querySelectorAll('video')].sort((a,b)=>{const ar=a.getBoundingClientRect();const br=b.getBoundingClientRect();return br.width*br.height-ar.width*ar.height})[0]
        """

    private static let playerStateJavaScript =
        """
        (()=>{const v=\(largestVideoExpression);if(!v)return JSON.stringify({error:'no_video'});const r=v.getBoundingClientRect();const xOffset=Math.max((window.outerWidth-window.innerWidth)/2,0);const yOffset=Math.max(window.outerHeight-window.innerHeight,0);return JSON.stringify({x:xOffset+r.left,y:yOffset+r.top,width:r.width,height:r.height})})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let togglePlaybackJavaScript =
        """
        (()=>{const v=\(largestVideoExpression);if(!v)return 'no_video';if(v.paused){v.play()}else{v.pause()}return String(v.paused)})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let seekJavaScript =
        """
        (()=>{const v=\(largestVideoExpression);if(!v)return 'no_video';const next=Math.max(0,Math.min(Number.isFinite(v.duration)?v.duration:Number.MAX_SAFE_INTEGER,v.currentTime+(__SECONDS__)));v.currentTime=next;return String(v.currentTime)})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let installPictureInPictureJavaScript =
        """
        (()=>{const v=\(largestVideoExpression);if(!v||!document.pictureInPictureEnabled)return 'no_video';const seek=(seconds)=>{const duration=Number.isFinite(v.duration)?v.duration:Number.MAX_SAFE_INTEGER;v.currentTime=Math.max(0,Math.min(duration,v.currentTime+seconds))};const bind=(action,handler)=>{try{navigator.mediaSession.setActionHandler(action,handler)}catch(_){}};bind('enterpictureinpicture',()=>{if(!document.pictureInPictureElement){v.requestPictureInPicture().catch(()=>{})}});bind('play',()=>v.play());bind('pause',()=>v.pause());bind('seekbackward',details=>seek(-(details.seekOffset||10)));bind('seekforward',details=>seek(details.seekOffset||10));bind('previoustrack',()=>seek(-10));bind('nexttrack',()=>seek(10));try{navigator.mediaSession.playbackState=v.paused?'paused':'playing'}catch(_){};window.__panecuePictureInPictureVideo=v;return 'ready'})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let exitPictureInPictureJavaScript =
        """
        (()=>{if(document.pictureInPictureElement){document.exitPictureInPicture().catch(()=>{})}return 'ok'})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let installPictureInPictureTriggerJavaScript =
        """
        (()=>{const v=window.__panecuePictureInPictureVideo||\(largestVideoExpression);if(!v)return 'no_video';document.getElementById('__panecue_pip_trigger')?.remove();const r=v.getBoundingClientRect();const b=document.createElement('button');b.id='__panecue_pip_trigger';b.setAttribute('aria-label','Open PaneCue video');Object.assign(b.style,{position:'fixed',left:`${r.left}px`,top:`${r.top}px`,width:`${r.width}px`,height:`${r.height}px`,margin:'0',padding:'0',border:'0',opacity:'0.001',zIndex:'2147483647',cursor:'default'});b.addEventListener('click',async e=>{e.preventDefault();e.stopImmediatePropagation();try{await v.requestPictureInPicture()}finally{b.remove()}},{capture:true,once:true});document.documentElement.appendChild(b);return 'ready'})()
        """
        .replacingOccurrences(of: "\n", with: "")

    private static let removePictureInPictureTriggerJavaScript =
        """
        (()=>{document.getElementById('__panecue_pip_trigger')?.remove();return 'ok'})()
        """
        .replacingOccurrences(of: "\n", with: "")
}
