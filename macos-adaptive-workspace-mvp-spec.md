# Adaptive Workspace for macOS

## MVP Technical Specification

- Status: Draft for implementation
- Platform: macOS, single built-in display
- Companion: Google Chrome extension, Manifest V3
- Product language: Russian first; localization-ready
- Updated: 2026-07-23

## 1. Product intent

Adaptive Workspace is not another manual tiling utility. Its value is that the user does not need to decide which layout to use every time.

The product observes the current work context, activates a predefined scenario, moves only the necessary windows, keeps an immediate undo path, and restores the previous workspace when the scenario ends.

Core product rule:

> If the user repeatedly chooses windows, ratios, and snap zones, the product has failed.

### Runtime experience

1. A relevant context remains stable for a short debounce period.
2. The app selects the highest-priority matching scenario.
3. It snapshots the current workspace.
4. It applies the scenario automatically or, during trust-building, shows one compact confirmation.
5. It displays a temporary `Undo` action.
6. It restores the snapshot when the scenario ends.

Routine use must not require opening a dashboard or settings window.

## 2. MVP scope

### Included

- macOS menu-bar application.
- Accessibility-based observation and movement of third-party windows.
- Four built-in scenarios:
  - Call.
  - Code + Call.
  - Documentation + Code.
  - Notes + Browser.
- Scenario priority and conflict resolution.
- Snapshot, undo, and automatic restoration.
- Pause/freeze automation.
- One global `Optimize now` shortcut.
- Chrome Video Bridge extension.
- Extraction of a normal HTML video into Picture-in-Picture.
- Site adapters for an initial, deliberately small set of browser-call products.
- Local-only configuration and event processing.
- Single active Space and one built-in MacBook display.

### Excluded from the first release

- Multiple displays.
- Cross-Space window movement.
- Safari, Firefox, and Edge extensions.
- Machine-learning models.
- Cloud accounts or synchronization.
- Universal support for every conferencing website.
- Pixel-cropping video through ScreenCaptureKit.
- Arbitrary user-authored automation scripts.
- Closing applications or destroying unsaved state.

## 3. UX principles

### 3.1 Zero-decision runtime

The user configures preferences once. A running scenario should expose at most:

- scenario name;
- `Undo`;
- `Pause automation`.

### 3.2 Trust is progressive

Each scenario supports three modes:

- `suggest`: show a compact confirmation before changing windows;
- `automatic`: apply without confirmation and show `Undo`;
- `disabled`: never activate automatically.

Default onboarding behavior is `suggest`. After two accepted activations, the app may offer to switch that scenario to `automatic`. It must never change the mode silently.

### 3.3 Never fight the user

When the user manually moves or resizes a managed window:

- freeze the active scenario until it ends;
- preserve the user’s new arrangement;
- do not immediately reapply the original layout;
- record only a local correction counter for later suggestions.

Learning custom layouts is outside the MVP.

### 3.4 Stable scenarios

- A trigger must remain true for at least 1.5 seconds.
- An active scenario remains sticky while its terminating condition is false.
- Focus changes alone must not continuously swap window sizes.
- A scenario cannot reapply more than once in 10 seconds without a new explicit trigger.

### 3.5 Restoration is mandatory

Before any change, store:

- application bundle identifier;
- process identifier;
- window identifier when available;
- window title fingerprint;
- frame;
- minimized/hidden state;
- active application;
- screen;
- Space context when observable.

Restoration is best-effort for windows that were closed or recreated, but failures must never affect unrelated windows.

## 4. Application roles

The engine reasons about roles, not hard-coded products.

| Role | Examples | Selection rule |
|---|---|---|
| IDE | Xcode, VS Code, JetBrains IDEs | Most recently active eligible IDE window |
| Browser | Google Chrome | Most recently active normal browser window |
| Documentation | Chrome tab classified as technical documentation | Active documentation tab or most recent matching tab |
| Notes | Apple Notes, Obsidian, Notion, another user-selected app | Most recently active eligible notes window |
| Meeting | Native call client or supported browser meeting tab | Active conference session |
| Video | Selected browser `<video>` or conference video surface | Highest-scoring eligible video candidate |

Users can remap applications to roles in settings. Bundle identifiers and URL rules are data, not scenario-engine code.

## 5. Scenario priority

| Priority | Scenario |
|---:|---|
| 100 | Code + Call |
| 90 | Call |
| 60 | Documentation + Code |
| 50 | Notes + Browser |

Rules:

- Only one scenario owns the workspace at a time.
- A higher-priority scenario may suspend a lower-priority scenario.
- When the higher-priority scenario ends, restore its snapshot first.
- Re-evaluate the restored workspace after a two-second cooldown.
- A user-initiated `Undo` suppresses the same automatic scenario for 10 minutes or until manually re-enabled.

## 6. Built-in scenarios

## 6.1 Call

### Purpose

Keep the current work visible while showing only the useful video surface from the meeting.

### Entry trigger

Any one of:

- Chrome Video Bridge reports an active supported conference;
- a recognized native meeting application reports an active meeting window;
- the user invokes `Call` manually.

The trigger must remain stable for 1.5 seconds.

### Main-window selection

1. Most recently active non-meeting window from the preceding 10 minutes.
2. Most recently active Notes window.
3. Most recently active browser window that is not the meeting.
4. If none exists, do not rearrange the workspace; manage only the video tile.

### Layout

- Main work window: entire `NSScreen.visibleFrame`.
- Video: floating PiP, default `260 × 146 pt`.
- PiP position: right edge, vertically centered, with `16 pt` margin.
- Other nonessential windows: minimized or hidden according to per-app preference.
- Never close applications.

PiP size is clamped:

```text
width  = clamp(220, visibleWidth × 0.22, 320)
height = width × 9 / 16
```

### Exit trigger

- conference inactive for five seconds;
- user ends the scenario;
- meeting application closes.

### Exit behavior

- close only a PiP surface created by Adaptive Workspace;
- restore the captured workspace snapshot;
- return focus to the previously active application.

### Fallback

If video extraction is unavailable:

- keep the entire call window at `320 × 240 pt` on the right;
- show `Video extraction unavailable`;
- do not request Screen Recording permission in the MVP.

## 6.2 Code + Call

### Purpose

Keep the IDE dominant while retaining a small view of the call.

### Entry trigger

- a Call trigger is active; and
- an IDE was the most recently active non-meeting application.

### Layout

- IDE: entire visible frame.
- Video PiP: `240 × 135 pt`, right edge.
- Default vertical position: upper-right, below the menu bar.
- Browser documentation, chat, and other windows: hidden or minimized.

The user can select one of four PiP corners in settings. The scenario must remember that choice.

### Behavior

- IDE remains primary regardless of temporary focus changes.
- Opening documentation does not automatically replace the IDE.
- A global shortcut may temporarily raise the most recent documentation window without changing the active scenario.

### Exit

End with the Call trigger and restore the pre-call snapshot. Do not immediately force Documentation + Code; wait for the global two-second cooldown and re-evaluate.

## 6.3 Documentation + Code

### Purpose

Show code and technical documentation side by side without manual tiling.

### Entry trigger

- one eligible IDE window exists;
- Chrome Video Bridge classifies the active browser tab as documentation, or the browser title matches a local documentation rule;
- no call scenario is active;
- the condition remains stable for 1.5 seconds.

### Layout

- IDE: left, primary.
- Documentation: right, secondary.
- Gap: `8 pt`.
- Target ratio: `65 / 35`.
- Secondary width:

```text
secondaryWidth = clamp(360, visibleWidth × 0.35, 480)
primaryWidth   = visibleWidth - secondaryWidth - gap
```

### Behavior

- Focus changes do not swap the two windows.
- The browser stays on the right until the scenario ends or the user manually changes the layout.
- Unrelated browser windows are ignored.

### Exit

- IDE or documentation window closes;
- active documentation tab is replaced by a non-documentation tab for more than 10 seconds;
- user freezes or undoes the scenario.

## 6.4 Notes + Browser

### Purpose

Support research and note-taking, including browser video without wasting space on Chrome chrome.

### Entry trigger

- an eligible Notes window and Chrome window exist;
- no call or code scenario has higher priority;
- one of those two applications was activated recently.

### Normal layout

- Browser: left, `60%`.
- Notes: right, `40%`.
- Gap: `8 pt`.
- The arrangement remains fixed during ordinary focus switching.

### Video branch

When Video Bridge reports an actively playing eligible video:

1. extract the selected video into PiP;
2. expand Notes to the full visible frame;
3. keep the originating Chrome window alive but hidden behind Notes;
4. place PiP at the right edge, default `320 × 180 pt`;
5. restore the normal `60 / 40` layout when PiP closes or playback ends.

This branch is for note-taking from a video. It must not activate for muted decorative videos, animated backgrounds, advertisements, or tiny preview players.

### Exit

- either application closes;
- both applications remain inactive for 30 seconds and another eligible scenario appears;
- user undoes or freezes automation.

## 7. Chrome Video Bridge

## 7.1 Purpose

The macOS Accessibility API sees Chrome windows, not semantic video elements inside a web page. Video Bridge provides that missing browser context.

The extension must:

- discover eligible `<video>` elements;
- classify normal playback versus a conference;
- request PiP after a valid user action when required;
- report sanitized context to the native app;
- never send video frames, audio, page content, or browsing history to a server.

## 7.2 Extension architecture

```text
Content Script
  └─ Video scanner and site adapter
       ↓ runtime messaging
Manifest V3 Service Worker
  ├─ Permission coordinator
  ├─ PiP command coordinator
  └─ Native Messaging client
       ↓ JSON over stdio
macOS Native Messaging Host
       ↓ local IPC
Adaptive Workspace app
```

Chrome content scripts can inspect and modify page DOM. Programmatic injection requires host permission or temporary `activeTab` permission. Native Messaging allows the extension service worker to exchange messages with a registered macOS host.

References:

- [Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)
- [Chrome extension permissions](https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions)
- [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

## 7.3 Permissions

Required extension permissions:

```json
{
  "permissions": [
    "activeTab",
    "scripting",
    "storage",
    "nativeMessaging"
  ],
  "optional_host_permissions": [
    "https://*/*"
  ]
}
```

Policy:

- Do not request all-host access at installation.
- Ask for optional host access only when the user enables automatic extraction for a site.
- Manual extraction uses `activeTab` when possible.
- Show the exact origin being granted.
- Never request cookies, browsing history, downloads, webRequest, or clipboard permissions.

## 7.4 Video candidate selection

For every visible `<video>`, calculate a score:

```text
score =
  visibleAreaWeight
  + playingWeight
  + audibleWeight
  + viewportWeight
  + conferenceAdapterWeight
  - tinyVideoPenalty
  - mutedAutoplayPenalty
  - advertisementPenalty
```

Minimum generic eligibility:

- element has a video track;
- rendered size is at least `240 × 135 CSS px`;
- at least 60% of the element is visible in the viewport;
- element is playing, or a conference adapter marks it active;
- element is not identified as decorative or an advertisement.

If two candidates have similar scores, require the user to choose once and remember the site-specific preference.

## 7.5 PiP modes

### Standard video PiP

Use `HTMLVideoElement.requestPictureInPicture()` for a single normal video element.

Advantages:

- simplest implementation;
- native always-on-top behavior;
- low processing overhead;
- no video pixels pass through the macOS application.

### Document Picture-in-Picture

Use for supported conference adapters that need:

- multiple participant videos;
- compact mute/leave controls;
- custom conferencing layout.

Chrome’s Document Picture-in-Picture can display arbitrary HTML in an always-on-top window. Opening normally requires a user gesture, and the website cannot choose the final screen position.

Reference:

- [Chrome Document Picture-in-Picture](https://developer.chrome.com/docs/web-platform/document-picture-in-picture/)

### User-gesture rule

Generic automatic extraction cannot be promised for every site.

Behavior:

- if the site supports automatic PiP, use it;
- otherwise show one compact prompt: `Video found — press shortcut to detach`;
- the Chrome extension shortcut performs the extraction;
- after PiP opens, the macOS app positions it and continues automatically.

Browser-initiated Auto PiP does not provide a universal call solution and has restrictions for pages using camera or microphone.

Reference:

- [Chrome automatic Picture-in-Picture](https://developer.chrome.com/blog/automatic-picture-in-picture-initiated-by-the-browser)
- [Chrome Commands API](https://developer.chrome.com/docs/extensions/reference/api/commands)

## 7.6 Initial adapters

MVP adapter order:

1. Generic single `<video>` pages.
2. One selected browser conferencing product.
3. A second conferencing product only after the first adapter is reliable.

Do not claim universal meeting support. Conference DOM structures can change without notice; adapters must be independently versioned and covered by smoke tests.

## 7.7 Native Messaging protocol

All messages are JSON and schema-validated. The native host accepts messages only from the production extension identifier.

### Extension to macOS

```json
{
  "type": "context.changed",
  "version": 1,
  "payload": {
    "tabId": 42,
    "origin": "https://example.com",
    "pageKind": "documentation",
    "hasEligibleVideo": true,
    "conferenceActive": false,
    "candidateCount": 1
  }
}
```

```json
{
  "type": "video.pipOpened",
  "version": 1,
  "payload": {
    "mode": "video",
    "origin": "https://example.com",
    "aspectRatio": 1.7778
  }
}
```

```json
{
  "type": "conference.stateChanged",
  "version": 1,
  "payload": {
    "origin": "https://example.com",
    "active": true
  }
}
```

### macOS to extension

```json
{
  "type": "video.extract",
  "version": 1,
  "payload": {
    "tabId": 42,
    "preferredMode": "video"
  }
}
```

```json
{
  "type": "video.closeAdaptivePip",
  "version": 1,
  "payload": {}
}
```

Do not transmit:

- full page text;
- full URL paths or query strings;
- video or audio frames;
- participant names;
- chat messages;
- authentication data.

## 8. macOS application architecture

## 8.1 Technology

- Swift.
- AppKit for window/system integration.
- SwiftUI where useful for settings and onboarding.
- Menu-bar app using `LSUIElement`.
- Initial deployment target: macOS 14 or newer.
- No network backend.

## 8.2 Modules

| Module | Responsibility |
|---|---|
| `WorkspaceObserver` | App launch, termination, activation, Space and screen changes |
| `AXWindowProvider` | Enumerate, identify, observe, move, resize, minimize, and activate windows |
| `ContextStore` | Maintain recent focus history and browser context |
| `RoleClassifier` | Map applications and tabs to IDE, Notes, Documentation, Meeting, and Video |
| `ScenarioEngine` | Evaluate triggers, priorities, debounce, cooldown, and active scenario |
| `LayoutPlanner` | Convert a scenario into target rectangles |
| `LayoutExecutor` | Snapshot, apply, undo, restore, and handle partial failures |
| `VideoBridgeClient` | Communicate with the Chrome native host |
| `StatusController` | Menu-bar state, prompt, undo toast, pause |
| `SettingsStore` | Local scenario modes, app-role mappings, PiP corner, and permissions state |

## 8.3 System APIs

- `NSWorkspace` notifications for application launch, termination, activation, hiding, and Space changes.
- `AXUIElement` to control accessible third-party application windows.
- `AXUIElementSetAttributeValue` for settable position and size attributes.
- `NSScreen.visibleFrame` for the safe work area excluding the menu bar, Dock, and camera housing.

References:

- [Apple NSWorkspace notifications](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Apple AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)
- [Apple NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)

## 8.4 Window identity

Use a composite identity:

```text
bundleIdentifier
+ processIdentifier
+ AX window identifier when exposed
+ normalized title fingerprint
+ initial frame proximity
```

No individual field is reliable across all applications. Restoration must tolerate missing or recreated windows.

## 8.5 Coordinate system

Accessibility window position uses global coordinates with origin at the top-left of the primary screen. AppKit screen frames use a bottom-left origin.

Create one tested coordinate-conversion module and do not duplicate conversions throughout the codebase.

Reference:

- [Apple kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)

## 8.6 Scenario state machine

```text
Idle
  → Candidate
  → Suggesting | Applying
  → Active
  → SuspendedByUser
  → Restoring
  → Idle
```

Transitions:

- `Idle → Candidate`: trigger becomes true.
- `Candidate → Idle`: trigger becomes false during debounce.
- `Candidate → Suggesting`: scenario mode is `suggest`.
- `Candidate → Applying`: scenario mode is `automatic`.
- `Suggesting → Applying`: user accepts.
- `Active → SuspendedByUser`: user moves a managed window or pauses automation.
- `Active → Restoring`: exit trigger or undo.
- `SuspendedByUser → Restoring`: scenario ends.
- `Restoring → Idle`: restoration completes or safely times out.

## 8.7 Applying a layout

1. Validate Accessibility permission.
2. Resolve window identities.
3. Capture snapshot.
4. Calculate `visibleFrame` at execution time.
5. Unminimize target windows.
6. Set target size and position.
7. Activate the primary application.
8. Hide or minimize only scenario-owned secondary windows.
9. Position PiP if its Accessibility attributes are settable.
10. Show temporary `Undo`.

If an application rejects a position or size attribute:

- log a local diagnostic event;
- leave that window unchanged;
- continue safely with the remaining windows;
- never retry in a tight loop.

## 8.8 Undo and restoration

- Keep an in-memory stack of the last 10 snapshots.
- Persist only the currently active scenario snapshot for crash recovery.
- Remove persisted snapshots after successful restoration.
- On next launch after a crash, offer `Restore previous workspace`; do not restore automatically.

## 9. Permissions and onboarding

## 9.1 Required macOS permission

### Accessibility

Purpose:

- enumerate accessible windows;
- move and resize them;
- observe user window changes.

Onboarding must explain the benefit before opening System Settings.

## 9.2 Optional permissions

### Notifications

Used for scenario suggestions when the app is not frontmost. The app must remain usable without notification permission.

### Chrome extension

Required only for:

- documentation tab classification;
- browser conference detection;
- browser video extraction.

### Screen Recording

Not requested in the MVP.

ScreenCaptureKit can capture displays, applications, and windows, but introducing it would add a sensitive permission and a heavier video pipeline. Also, `sourceRect` is not used when capturing a single window, so semantic in-window extraction still requires extension-provided geometry plus local frame cropping.

References:

- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple sourceRect behavior](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect)

## 9.3 Onboarding sequence

1. Explain the product in one sentence.
2. Request Accessibility permission.
3. Run a safe test using two demo windows or currently open user-selected windows.
4. Offer Chrome Video Bridge installation.
5. Ask which applications represent IDE and Notes.
6. Enable all scenarios in `suggest` mode.
7. Show the global `Optimize now` shortcut.

## 10. Privacy and security

- All scenario evaluation is local.
- No analytics or telemetry in the first release.
- No screenshots, video frames, audio, document content, or participant information leave the device.
- Store only app roles, scenario preferences, ratios, and sanitized origins.
- Chrome host permissions are optional and origin-scoped.
- Validate every message received from a content script or native host.
- Treat content-script messages as untrusted input.
- Native Messaging accepts only the expected extension identifier.
- The app never closes user windows or applications.
- The app never modifies browser page content beyond what is necessary to open or restore PiP.

## 11. Storage model

Use a versioned local JSON or Codable property-list model.

```swift
struct ScenarioPreferences: Codable {
    let schemaVersion: Int
    var scenarios: [ScenarioID: ScenarioPreference]
    var appRoleMappings: [String: AppRole]
    var sitePermissions: [String: SitePermissionState]
    var preferredPiPCorner: PiPCorner
    var globalAutomationPaused: Bool
}

struct ScenarioPreference: Codable {
    var activationMode: ActivationMode
    var acceptedSuggestionCount: Int
    var suppressionUntil: Date?
    var primaryRatio: Double?
}
```

Do not persist window titles, focus history, or full URLs after the session ends.

## 12. Global shortcuts

Recommended application shortcuts:

- `Control + Option + Space`: Optimize current workspace.
- `Control + Option + Z`: Undo last layout.
- `Control + Option + P`: Pause or resume automation.

Recommended Chrome extension shortcut:

- `Command + Shift + 9`: Detach the best video candidate.

All shortcuts must be editable and checked for collisions during onboarding.

## 13. Acceptance criteria

## 13.1 General

- The application launches as a menu-bar utility without a Dock icon.
- Accessibility permission status is detected correctly.
- No scenario closes an application or window.
- `Undo` returns restorable windows to within `±2 pt` of the original frame.
- A manual resize freezes automation for the current scenario.
- The same scenario is not applied repeatedly during normal focus switching.
- A higher-priority scenario safely suspends a lower-priority one.

## 13.2 Call

- Starting a supported conference activates Call within two seconds after debounce.
- The previous working window becomes primary.
- Extracted video appears as a small right-side PiP.
- Ending the call restores the original workspace.
- If extraction fails, the product shows a clear fallback rather than silently resizing Chrome.

## 13.3 Code + Call

- An active IDE plus conference selects Code + Call instead of Call.
- IDE occupies the safe visible frame.
- PiP does not exceed 22% of visible screen width.
- Temporary app focus changes do not rearrange the workspace.

## 13.4 Documentation + Code

- A recognized documentation tab plus IDE activates the scenario.
- IDE and documentation use the configured ratio.
- Switching focus between the two does not swap their sizes or positions.
- Navigating away from documentation ends the scenario only after the exit delay.

## 13.5 Notes + Browser

- Notes and browser use `40 / 60` without video.
- Eligible browser video can be detached with one shortcut.
- After extraction, Notes occupies the main workspace and Chrome UI no longer consumes visible space.
- Closing PiP restores the normal Notes + Browser arrangement.

## 13.6 Video Bridge

- The extension installs without all-sites host permission.
- Manual video extraction works on the initial generic-video test set.
- Permission is requested only for the active origin when automatic operation is enabled.
- Native Messaging rejects unknown message versions and invalid schemas.
- No full URL, DOM content, audio, or video frames are sent to the native app.

## 13.7 Performance

- Idle CPU target: below 1% on a typical supported Mac.
- Idle memory target: below 100 MB.
- Scenario evaluation after an event: below 50 ms.
- Window layout application: below 700 ms excluding slow third-party applications.
- No polling loop faster than once per second; prefer system and Accessibility notifications.

## 14. Test matrix

### Display conditions

- 13-inch and 14-inch MacBook logical resolutions.
- Dock visible, hidden, left, right, and bottom.
- Menu bar visible and automatically hidden.
- Display scaling changed while the app runs.

### Window conditions

- Window minimized before scenario entry.
- Window closed during an active scenario.
- Application restarted with a new process identifier.
- Window refuses Accessibility size or position changes.
- User moves a managed window during automation.
- Native macOS full-screen window present.
- Multiple windows from the same application.

### Video conditions

- One normal playing `<video>`.
- Multiple videos with one dominant player.
- Muted autoplay advertisement.
- Video inside an iframe.
- Conference adapter active.
- PiP closed manually.
- Tab navigates while PiP is active.
- Browser quits during an active scenario.
- Site permission revoked.

## 15. Delivery milestones

## Milestone 0 — Feasibility spike

- Enumerate and move windows in Xcode, Chrome, Notes, and one additional IDE.
- Snapshot and restore frames.
- Verify PiP window discoverability and settable position.
- Prove Native Messaging between an unpacked Chrome extension and the macOS host.
- Prove standard `<video>` extraction from a test page.

Exit condition: no blocker to window movement, restoration, or Chrome-native communication.

## Milestone 1 — Window core

- `WorkspaceObserver`.
- `AXWindowProvider`.
- coordinate conversion.
- `LayoutPlanner`.
- snapshot, undo, restoration.
- menu-bar status and pause.

Exit condition: deterministic manual activation of all four layouts without browser semantics.

## Milestone 2 — Scenario engine

- roles and mappings;
- trigger evaluation;
- priority;
- debounce and cooldown;
- user override detection;
- `suggest`, `automatic`, and `disabled` modes.

Exit condition: native-app scenarios activate and restore reliably without oscillation.

## Milestone 3 — Chrome Video Bridge

- MV3 extension;
- content-script scanner;
- generic video PiP;
- native messaging;
- documentation classification;
- first conference adapter;
- permission UX.

Exit condition: Notes + Browser video branch and one browser-call flow pass acceptance tests.

## Milestone 4 — Onboarding and resilience

- Accessibility onboarding;
- Chrome installation guide;
- safe test flow;
- crash-recovery snapshot;
- diagnostics;
- localization.

Exit condition: a new user can reach the first successful scenario without developer assistance.

## Milestone 5 — Laptop QA

- full test matrix;
- performance checks;
- unsupported-app behavior;
- layout tuning at small logical resolutions;
- release packaging.

Exit condition: all MVP acceptance criteria pass on supported MacBook configurations.

## 16. Recommended first implementation slice

Build a vertical slice before implementing every scenario:

1. menu-bar app and Accessibility onboarding;
2. snapshot and restore two user-selected windows;
3. manual Documentation + Code layout;
4. Chrome extension with `activeTab`;
5. generic `<video>` detection and shortcut-triggered PiP;
6. Notes + Browser video branch;
7. automatic trigger and undo.

This slice validates the two hardest product promises:

- the app can rearrange and restore a real workspace safely;
- browser video can be separated without showing the full Chrome interface.

Only after this passes should conference-specific adapters and automatic Call scenarios be added.

## 17. Decisions still required

- Final product name.
- First supported browser conferencing product.
- Initial list of IDE and Notes application mappings.
- Default PiP corner.
- Distribution method for the macOS application and Chrome extension.
- Whether `suggest` should upgrade to `automatic` after two or three accepted activations.
