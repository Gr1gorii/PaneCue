# PaneCue

PaneCue is a privacy-conscious macOS workspace manager that arranges
application windows around the task you are doing. It combines reusable
layouts, a visual scenario editor, local automation, floating call or browser
video, and optional voice commands.

> [!IMPORTANT]
> PaneCue is an early macOS prototype. It is not yet notarized or distributed
> as a production-ready download.

PaneCue source code is available under the
[Mozilla Public License 2.0](LICENSE).

## v0.1 Product Freeze

The public-beta product contract is defined by:

- [Product brief](docs/product-freeze/v0.1/v0.1-product-brief.md)
- [Included, experimental, and deferred scope](docs/product-freeze/v0.1/v0.1-scope.md)
- [Primary user flow and failure behavior](docs/product-freeze/v0.1/v0.1-user-flow.md)
- [Platform and application support matrix](docs/product-freeze/v0.1/v0.1-support-matrix.md)
- [Automated acceptance gate and macOS smoke cases](docs/product-freeze/v0.1/v0.1-acceptance.md)
- [Release, privacy, interface, and success decisions](docs/product-freeze/v0.1/v0.1-decisions.md)

The repository now packages two explicit profiles from the same codebase:

- **PaneCue** is the v0.1 candidate. It opens directly in Arrange, processes
  commands locally, and contains no active browser-video, call-capture,
  cloud-voice, BYOK, or Suggestions Beta entry points.
- **PaneCue Experimental** preserves the prototype video, cloud voice,
  alternative-model, and Suggestions Beta work behind a separately identified
  app bundle.

The prototype description below records experimental capabilities that are
intentionally excluded from the v0.1 public-beta build.

PaneCue now opens as a regular macOS application with Arrange, Cues, and
Settings. Closing the main window does
not quit the app: the PaneCue icon remains in the menu bar for quick access,
and reopening the Dock icon restores the window.

Cues can be imported from and exported to versioned `.panecuecue.json` files.
Imports preserve existing Cues, regenerate identifiers, and disable only
conflicting activation phrases or shortcuts. Settings also provides a local
diagnostics preview with manual JSON export and Reset Personalization for
removing saved command corrections without deleting Cues or credentials.

On first launch, the stable app opens directly in Arrange without requesting
permissions. Accessibility is requested contextually after the first explicit
Apply. Optional offline speech becomes available after that first successful
text arrangement.

Immediately before Apply, PaneCue refreshes the target-window inventory and
blocks closed, ambiguous, minimized, full-screen, or non-resizable targets
with a visible reason. The result lists every target as moved, unchanged,
skipped, or failed. A complete Apply offers Undo beside the result; a partial
Apply offers Rollback for the snapshotted windows.

PaneCue Experimental retains a guided setup that explains its additional
permissions before requesting them.

The experimental profile supports four built-in scenarios, Cues, Suggestions
Beta, automatic application launching, and cloud voice routing:

- **Code + Call** recognizes an IDE and a native or browser meeting, keeps the IDE dominant, and shows the call in a PaneCue-owned floating panel.
- **Documentation + Code** places a recognized code editor at 65% and a browser, Preview, or Dash at 35%.
- **Notes + Browser** places a browser at 65% and Apple Notes, Notion, Obsidian, Bear, Craft, or another recognized notes app at 35%.
- **Browser Video** opens the active Chrome player in Chrome's native
  Picture-in-Picture window without leaving a technical browser window at an
  edge of the screen. The source tab moves into the background while the
  browser remains free for other work. Close, play/pause, and ±10 second
  controls appear only while the pointer is over the video. Closing Picture
  in Picture restores the original tab automatically. Other browsers use
  visual player detection and never reveal the full browser while PaneCue is
  still looking for a player.

**Suggestions Beta** runs locally and watches only application/window metadata. It
uses the active and previously active application to suggest Code + Call,
Documentation + Code, or Notes + Browser. A compact panel explains the
suggestion and waits for **Apply** or **Not now**; Auto Mode never rearranges
windows without approval. Rejected suggestions are snoozed for ten minutes,
and the setting is available both in the main window and the menu bar.

Built-in and custom scenarios launch required applications when they are
closed, wait until usable windows are available, then arrange them. Custom
scenarios can also open web URLs before applying the layout. Layouts snapshot
all affected windows and restore their exact previous frames on request.
PaneCue does not close applications, move windows between Spaces, or hide
unrelated windows.

FaceTime extraction uses ScreenCaptureKit and therefore requires Screen Recording permission. The current crop is tuned for FaceTime's idle camera view and normal call window.

Voice commands use `gpt-realtime-2.1-mini` only to choose between allow-listed
actions: the four built-in scenarios, saved custom scenarios, and
**Restore Previous Layout**. Press `⌥ Space`, speak a short Russian or English
command, then press `⌥ Space` again. Audio is captured only between those two
presses. Saved scenario names are sent as the allowed choices during a voice
request. A custom activation phrase can be assigned to each scenario; window
contents are not sent to the model.

For this local prototype, the user supplies an OpenAI API key and PaneCue stores it in macOS Keychain. The key is never displayed again or written to a project file. A distributed version should exchange a server-issued short-lived token instead of connecting with a long-lived user key.

## Requirements

- macOS 14 or newer
- Swift 6
- Accessibility permission for the packaged `PaneCue.app`
- Microphone permission only for voice commands
- Speech Recognition permission only for Automatic or Offline voice commands
- Screen Recording permission only for experimental floating call and browser video
- An OpenAI API key only in the experimental Automatic or Cloud voice modes

Full Xcode is not required for the current Swift Package prototype.

## Build and test

```sh
swift test
./scripts/package_app.sh
open build/PaneCue.app
```

Before publishing a v0.1 candidate, run the complete automated gate:

```sh
./scripts/run_v01_acceptance.sh
```

Release engineering is documented in
[the v0.1 release guide](docs/release/v0.1-release.md). A local DMG can be
created with `./scripts/build_release_dmg.sh --adhoc`; public artifacts require
a Developer ID Application certificate and successful Apple notarization.
Apple Developer enrollment is intentionally deferred while v0.1 is qualified
locally.

To build the separate experimental app:

```sh
./scripts/package_app.sh --experimental
open "build/PaneCue Experimental.app"
```

The PaneCue Experimental first-launch setup lets you choose how voice commands are processed:

- **Automatic** uses OpenAI while online and the local pack without internet.
- **Offline Only** keeps audio and command text on the Mac.
- **Cloud Only** keeps local models unloaded from memory.

The wizard then walks through Accessibility, Screen Recording, Microphone,
and—when local processing is enabled—Speech Recognition. A skipped permission
can be granted later from the Settings screen.

Choose **OpenAI API Key…** from the menu or Settings and paste a key once.
PaneCue stores it in macOS Keychain, not in project files or UserDefaults.

For exact Chrome video extraction and controls, enable:

```text
Chrome → View → Developer → Allow JavaScript from Apple Events
```

macOS may also ask once whether PaneCue can automate Google Chrome. This access
is requested only when **Browser Video** is selected and is used only to
identify the selected video, open native Picture in Picture, restore its
source tab, and connect play/pause and ten-second seek controls.

## Privacy

- **Auto Mode** observes application and window metadata locally. It does not
  read window contents and never rearranges anything without approval.
- **Accessibility** is used to find, move, resize, and restore windows.
- **Screen Recording** is used only when extracting call or browser video.
- **Microphone** capture starts and stops with an explicit voice command.
- **Offline voice** uses macOS on-device transcription and the bundled
  PaneCue Mini model.
- **Cloud voice** sends the captured command audio to OpenAI for the selected
  allow-listed action. Window contents are not included.
- The OpenAI API key is stored in macOS Keychain and is never committed to the
  repository.

Choose **Custom Scenarios** to open Scenario Editor 2.0. Each scenario can:

- arrange two to eight windows on a draggable 24 × 16 grid, with smooth
  movement and resize handles on every side and corner;
- match a specific application or a role such as any browser, IDE, meeting,
  notes, or documentation app;
- place each window on the main or external display;
- launch closed applications and open an optional URL;
- run only during a call or only while an external display is connected;
- use a custom Russian or English voice phrase and a global keyboard shortcut.

The editor also provides equal-column, focus-and-stack, and balanced-grid
presets. Saved layouts appear in the main window and the menu-bar shortcut.
Existing two-application scenarios are migrated automatically.

For **Code + Call**, select the scenario and PaneCue will launch a supported
editor or meeting app if necessary. Supported editors include Xcode, VS Code,
Cursor, Windsurf, JetBrains IDEs, Zed, Sublime Text, and Nova. Supported
meeting sources include Zoom, Teams, FaceTime, Webex, Skype, and recognized
meeting tabs in major browsers.

Use **Restore Previous Layout** to undo either change.

## Command Lab

Open **Command Lab** from the main-window sidebar to test PaneCue Mini without
moving any windows. Commands can be typed or transcribed fully on-device.
PaneCue turns the first command into an editable **Workspace Plan** for one to
eight windows. Follow-up commands reuse that visible context, so phrases such
as “make Notes even smaller,” “add Terminal at the bottom,” “swap the
windows,” “undo the last change,” and “save this as Development” work without
repeating the whole request.

The 24 × 16 preview grid supports direct dragging and resize handles on every
side and corner. The inspector can add, remove, replace, resize, move, and
swap windows, undo up to 30 draft changes, save the result as a reusable
scenario, or explicitly apply it. No application is launched and no real
window moves until **Apply Windows** is pressed. Saved language corrections
remain on this Mac and can contain a complete multi-window plan; a phrase can
also be remembered as **No Action**.

## Current structure

- `PaneCueCore`: Accessibility window inventory, layout calculation, snapshot, and restoration.
- `PaneCue`: menu-bar application shell, Keychain integration, microphone capture, and Realtime API client.
- `PaneCueCoreTests`: deterministic layout and coordinate tests.
- `scripts/package_app.sh`: builds and ad-hoc signs a local `.app` bundle.
- Voice processing can run in Automatic, Offline Only, or Cloud Only mode.
  Offline commands use on-device macOS speech recognition and the bundled
  500 KB PaneCue Mini v2 intent model with 499,975 learned parameters. It can
  also understand conversational
  two-window requests such as “open VS Code and make Notes a little smaller.”
  Qwen and FunctionGemma remain optional experiments and are never bundled or
  loaded by the default local mode.

See `macos-adaptive-workspace-mvp-spec.md` for the complete MVP specification.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change. Please use
the process in [SECURITY.md](SECURITY.md) for security-sensitive reports
instead of opening a detailed public issue.

## License

PaneCue source code is licensed under the
[Mozilla Public License 2.0](LICENSE).
