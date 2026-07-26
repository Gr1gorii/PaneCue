import AppKit
import PaneCueCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScenarioEditorController {
    private let store: CustomScenarioStore
    private let didChange: () -> Void
    private var windowController: NSWindowController?

    init(
        store: CustomScenarioStore,
        didChange: @escaping () -> Void
    ) {
        self.store = store
        self.didChange = didChange
    }

    func show() {
        if let window = windowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let editorView = ScenarioEditorView(
            initialScenarios: store.scenarios,
            applications: ApplicationCatalog.installedApplications(),
            onSave: { [weak self] scenarios in
                guard let self else {
                    return
                }
                store.replaceAll(with: scenarios)
                didChange()
            },
            onClose: { [weak self] in
                self?.windowController?.close()
                self?.windowController = nil
            }
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1_060,
                height: 720
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "PaneCue Cues"
        window.contentViewController = NSHostingController(
            rootView: editorView
        )
        window.minSize = NSSize(width: 900, height: 620)
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}

struct ScenarioEditorView: View {
    @State private var scenarios: [CustomScenario]
    @State private var selectedID: UUID?
    @State private var selectedWindowID: UUID?
    @State private var isGridExpanded = false
    @State private var transferMessage = ""
    @State private var transferError: String?

    let applications: [InstalledApplication]
    let onSave: ([CustomScenario]) -> Void
    let onClose: () -> Void

    init(
        initialScenarios: [CustomScenario],
        applications: [InstalledApplication],
        onSave: @escaping ([CustomScenario]) -> Void,
        onClose: @escaping () -> Void
    ) {
        let editableScenarios = initialScenarios.map { scenario in
            var copy = scenario
            if !PaneCueReleaseProfile.current.isExperimental {
                copy.conditions = ScenarioConditions()
            }
            return copy
        }
        _scenarios = State(initialValue: editableScenarios)
        _selectedID = State(initialValue: editableScenarios.first?.id)
        _selectedWindowID = State(
            initialValue: editableScenarios.first?.windows.first?.id
        )
        self.applications = applications
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                scenarioList
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 250)

                Divider()

                Group {
                    if let selectedIndex {
                        scenarioDetail(
                            scenario: $scenarios[selectedIndex]
                        )
                    } else {
                        ContentUnavailableView(
                            "No Cue Selected",
                            systemImage: "rectangle.3.group",
                            description: Text(
                                "Create or import a Cue, then arrange its windows on the grid."
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                Label(
                    validationMessage
                        ?? (
                            transferMessage.isEmpty
                                ? "Cues are stored only on this Mac."
                                : transferMessage
                        ),
                    systemImage: validationMessage == nil
                        ? "lock"
                        : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(
                    validationMessage == nil ? Color.secondary : Color.red
                )

                Spacer()

                Button {
                    importCues()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportSelectedCue()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedIndex == nil || validationMessage != nil)

                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Cues") {
                    onSave(scenarios)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .padding(14)
        }
        .frame(minWidth: 620, minHeight: 560)
        .onChange(of: selectedID) { _, newID in
            selectedWindowID = scenarios.first {
                $0.id == newID
            }?.windows.first?.id
        }
        .alert(
            "Cue Transfer Failed",
            isPresented: Binding(
                get: { transferError != nil },
                set: { if !$0 { transferError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                transferError = nil
            }
        } message: {
            Text(transferError ?? "Unknown error")
        }
    }

    private var scenarioList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MY CUES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(scenarios.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            List(selection: $selectedID) {
                ForEach(scenarios) { scenario in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            scenario.name.isEmpty
                                ? "Untitled Cue"
                                : scenario.name
                        )
                        .font(.body.weight(.medium))

                        Text(
                            "\(scenario.windows.count) windows · \(scenario.windows.map(\.target.displayName).joined(separator: ", "))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .tag(Optional(scenario.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 12) {
                Button {
                    addScenario()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Cue")

                Button {
                    duplicateSelectedScenario()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Duplicate Cue")
                .disabled(selectedID == nil)

                Button {
                    removeSelectedScenario()
                } label: {
                    Image(systemName: "minus")
                }
                .help("Delete Cue")
                .disabled(selectedID == nil)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .background(.background.opacity(0.45))
    }

    @ViewBuilder
    private func scenarioDetail(
        scenario: Binding<CustomScenario>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Cue")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(scenario.wrappedValue.windows.count) of 8 windows")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                editorSection("BASIC") {
                    TextField(
                        "Cue name",
                        text: scenario.name
                    )
                    .textFieldStyle(.roundedBorder)
                }

                editorSection("VISUAL LAYOUT") {
                    ScenarioGridEditor(
                        windows: scenario.windows,
                        selectedWindowID: $selectedWindowID,
                        canvasHeight: 360,
                        onExpand: {
                            isGridExpanded = true
                        }
                    )
                }

                editorSection("WINDOWS") {
                    windowList(scenario: scenario)

                    if let windowIndex = selectedWindowIndex(
                        in: scenario.wrappedValue
                    ) {
                        Divider()
                            .padding(.vertical, 4)
                        windowConfiguration(
                            window: scenario.windows[windowIndex],
                            number: windowIndex + 1
                        )
                    }
                }

                if PaneCueReleaseProfile.current.isExperimental {
                    editorSection("CONDITIONS · EXPERIMENTAL") {
                        Toggle(
                            "Only while a call window is open",
                            isOn: scenario.conditions.onlyDuringCall
                        )
                        Toggle(
                            "Only when an external display is connected",
                            isOn: scenario.conditions.requiresExternalDisplay
                        )
                    }
                }

                editorSection("ACTIVATION") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Voice phrase")
                            .font(.callout.weight(.medium))
                        TextField(
                            "For example: start research mode",
                            text: scenario.voicePhrase
                        )
                        .textFieldStyle(.roundedBorder)
                        Text(
                            "You can still say the Cue name if this is empty."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    hotKeyEditor(hotKey: scenario.hotKey)
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isGridExpanded) {
            ExpandedScenarioGridEditor(
                scenario: scenario,
                selectedWindowID: $selectedWindowID,
                onDone: {
                    isGridExpanded = false
                }
            )
        }
    }

    private func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background.opacity(0.62))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.7), lineWidth: 1)
            }
        }
    }

    private func windowList(
        scenario: Binding<CustomScenario>
    ) -> some View {
        VStack(spacing: 7) {
            ForEach(
                Array(scenario.wrappedValue.windows.enumerated()),
                id: \.element.id
            ) { index, window in
                Button {
                    selectedWindowID = window.id
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(
                                    selectedWindowID == window.id
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.14)
                                )
                            )
                            .foregroundStyle(
                                selectedWindowID == window.id
                                    ? Color.white
                                    : Color.secondary
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.target.displayName)
                                .font(.callout.weight(.medium))
                            Text(
                                "\(window.display.displayName) · \(window.launchIfNeeded ? "launch if needed" : "already open")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !window.urlString.isEmpty {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            removeWindow(
                                id: window.id,
                                from: scenario
                            )
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove Window")
                        .disabled(scenario.wrappedValue.windows.count <= 2)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(
                                selectedWindowID == window.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                addWindow(to: scenario)
            } label: {
                Label("Add window", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(scenario.wrappedValue.windows.count >= 8)
        }
    }

    private func windowConfiguration(
        window: Binding<ScenarioWindowSlot>,
        number: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Window \(number)")
                .font(.headline)

            Picker(
                "Match",
                selection: Binding(
                    get: { window.wrappedValue.target.kind },
                    set: { kind in
                        switch kind {
                        case .application:
                            if let application = applications.first {
                                window.wrappedValue.target =
                                    ScenarioWindowTarget(
                                        application: application
                                            .scenarioApplication
                                    )
                            }
                        case .role:
                            window.wrappedValue.target =
                                ScenarioWindowTarget(role: .browser)
                        }
                    }
                )
            ) {
                Text("Specific application")
                    .tag(ScenarioTargetKind.application)
                Text("Application role")
                    .tag(ScenarioTargetKind.role)
            }
            .pickerStyle(.segmented)

            if window.wrappedValue.target.kind == .application {
                Picker(
                    "Application",
                    selection: Binding(
                        get: {
                            window.wrappedValue.target.application?
                                .bundleIdentifier ?? ""
                        },
                        set: { identifier in
                            guard let application = applications.first(
                                where: {
                                    $0.bundleIdentifier == identifier
                                }
                            ) else {
                                return
                            }
                            window.wrappedValue.target =
                                ScenarioWindowTarget(
                                    application: application
                                        .scenarioApplication
                                )
                        }
                    )
                ) {
                    ForEach(applications) { application in
                        Text(application.displayName)
                            .tag(application.bundleIdentifier)
                    }
                }
            } else {
                Picker(
                    "Role",
                    selection: Binding(
                        get: {
                            window.wrappedValue.target.role ?? .browser
                        },
                        set: {
                            window.wrappedValue.target =
                                ScenarioWindowTarget(role: $0)
                        }
                    )
                ) {
                    ForEach(
                        ApplicationRole.allCases.filter { $0 != .other },
                        id: \.self
                    ) { role in
                        Text(role.displayName).tag(role)
                    }
                }
            }

            Picker("Display", selection: window.display) {
                ForEach(ScenarioDisplayTarget.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }

            Toggle(
                "Launch the matching app if it is closed",
                isOn: window.launchIfNeeded
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Open URL (optional)")
                    .font(.callout.weight(.medium))
                TextField(
                    "https://…",
                    text: window.urlString
                )
                .textFieldStyle(.roundedBorder)
                Text(
                    "PaneCue opens this page before arranging the windows."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func hotKeyEditor(
        hotKey: Binding<ScenarioHotKey>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard shortcut")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(hotKey.wrappedValue.displayName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                modifierToggle(
                    "⌃ Ctrl",
                    isOn: hotKey.usesControl
                )
                modifierToggle(
                    "⌥ Opt",
                    isOn: hotKey.usesOption
                )
                modifierToggle(
                    "⇧ Shift",
                    isOn: hotKey.usesShift
                )
                modifierToggle(
                    "⌘ Cmd",
                    isOn: hotKey.usesCommand
                )

                TextField(
                    "Key",
                    text: Binding(
                        get: { hotKey.wrappedValue.key },
                        set: {
                            hotKey.wrappedValue.key = String(
                                $0.uppercased().filter {
                                    $0.isLetter || $0.isNumber
                                }.prefix(1)
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)

                Button {
                    hotKey.wrappedValue.key = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Clear Shortcut")
                .disabled(hotKey.wrappedValue.key.isEmpty)
            }
        }
    }

    private func modifierToggle(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.button)
            .controlSize(.small)
    }

    private var selectedIndex: Int? {
        guard let selectedID else {
            return nil
        }
        return scenarios.firstIndex { $0.id == selectedID }
    }

    private func selectedWindowIndex(
        in scenario: CustomScenario
    ) -> Int? {
        if let selectedWindowID,
           let index = scenario.windows.firstIndex(
               where: { $0.id == selectedWindowID }
           ) {
            return index
        }
        return scenario.windows.indices.first
    }

    private var validationMessage: String? {
        let names = scenarios.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if names.contains(where: \.isEmpty) {
            return "Every Cue needs a name."
        }
        if Set(names.map { $0.lowercased() }).count != names.count {
            return "Cue names must be unique."
        }
        if scenarios.contains(where: {
            $0.windows.count < 2 || $0.windows.count > 8
        }) {
            return "Each Cue needs between 2 and 8 windows."
        }
        if scenarios.flatMap(\.windows).contains(where: {
            $0.target.kind == .application
                && ($0.target.application?.bundleIdentifier.isEmpty ?? true)
        }) {
            return "Choose an application for every application window."
        }
        if let invalidURL = scenarios.flatMap(\.windows)
            .map(\.urlString)
            .first(where: {
                !$0.isEmpty && !Self.isValidWebURL($0)
            }) {
            return "“\(invalidURL)” is not a valid web URL."
        }

        let phrases = scenarios.map {
            $0.voicePhrase.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        }.filter { !$0.isEmpty }
        if Set(phrases).count != phrases.count {
            return "Voice phrases must be unique."
        }

        let configuredHotKeys = scenarios.map(\.hotKey)
            .filter { !$0.key.isEmpty }
        if configuredHotKeys.contains(where: { !$0.isEnabled }) {
            return "A shortcut needs at least one modifier key."
        }
        let hotKeyNames = configuredHotKeys.map(\.displayName)
        if Set(hotKeyNames).count != hotKeyNames.count {
            return "Keyboard shortcuts must be unique."
        }
        return nil
    }

    private func addScenario() {
        var number = scenarios.count + 1
        var name = "New Cue \(number)"
        let usedNames = Set(scenarios.map { $0.name.lowercased() })
        while usedNames.contains(name.lowercased()) {
            number += 1
            name = "New Cue \(number)"
        }

        let targets: [ScenarioWindowTarget]
        if applications.count >= 2 {
            targets = [
                ScenarioWindowTarget(
                    application: applications[0].scenarioApplication
                ),
                ScenarioWindowTarget(
                    application: applications[1].scenarioApplication
                )
            ]
        } else {
            targets = [
                ScenarioWindowTarget(role: .ide),
                ScenarioWindowTarget(role: .browser)
            ]
        }

        let scenario = CustomScenario(
            name: name,
            windows: [
                ScenarioWindowSlot(
                    target: targets[0],
                    gridRect: .left
                ),
                ScenarioWindowSlot(
                    target: targets[1],
                    gridRect: .right
                )
            ]
        )
        scenarios.append(scenario)
        selectedID = scenario.id
        selectedWindowID = scenario.windows.first?.id
    }

    private func duplicateSelectedScenario() {
        guard let selectedIndex else {
            return
        }
        var copy = scenarios[selectedIndex]
        copy.id = UUID()
        copy.name = uniqueName(base: "\(copy.name) Copy")
        copy.voicePhrase = ""
        copy.hotKey = ScenarioHotKey()
        copy.windows = copy.windows.map {
            var window = $0
            window.id = UUID()
            return window
        }
        scenarios.append(copy)
        selectedID = copy.id
        selectedWindowID = copy.windows.first?.id
    }

    private func uniqueName(base: String) -> String {
        let usedNames = Set(scenarios.map { $0.name.lowercased() })
        if !usedNames.contains(base.lowercased()) {
            return base
        }
        var number = 2
        while usedNames.contains("\(base) \(number)".lowercased()) {
            number += 1
        }
        return "\(base) \(number)"
    }

    private func removeSelectedScenario() {
        guard let selectedIndex else {
            return
        }
        scenarios.remove(at: selectedIndex)
        selectedID = scenarios.indices.contains(selectedIndex)
            ? scenarios[selectedIndex].id
            : scenarios.last?.id
    }

    private func addWindow(to scenario: Binding<CustomScenario>) {
        let index = scenario.wrappedValue.windows.count
        let target: ScenarioWindowTarget
        if !applications.isEmpty {
            target = ScenarioWindowTarget(
                application: applications[index % applications.count]
                    .scenarioApplication
            )
        } else {
            target = ScenarioWindowTarget(role: .browser)
        }
        let window = ScenarioWindowSlot(
            target: target,
            gridRect: ScenarioGridRect(
                x: 0.67,
                y: Double(max(index - 1, 0)) * 0.25,
                width: 0.33,
                height: 0.25
            )
        )
        scenario.wrappedValue.windows.append(window)
        selectedWindowID = window.id
        ScenarioGridEditor.applyGridPreset(to: &scenario.wrappedValue.windows)
    }

    private func removeWindow(
        id: UUID,
        from scenario: Binding<CustomScenario>
    ) {
        guard scenario.wrappedValue.windows.count > 2,
              let index = scenario.wrappedValue.windows.firstIndex(
                  where: { $0.id == id }
              )
        else {
            return
        }
        scenario.wrappedValue.windows.remove(at: index)
        selectedWindowID = scenario.wrappedValue.windows[
            min(index, scenario.wrappedValue.windows.count - 1)
        ].id
    }

    private func importCues() {
        let panel = NSOpenPanel()
        panel.title = "Import PaneCue Cues"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2_000_000 else {
                throw CueTransferError.fileTooLarge
            }
            let archive = try CueArchive.decode(Data(contentsOf: url))
            var adjustedCount = 0
            var imported: [CustomScenario] = []

            for cue in archive.cues {
                var copy = cue
                copy.id = UUID()
                copy.name = uniqueName(base: cue.name)
                if !PaneCueReleaseProfile.current.isExperimental {
                    copy.conditions = ScenarioConditions()
                }
                copy.windows = cue.windows.map { window in
                    var copy = window
                    copy.id = UUID()
                    return copy
                }

                let phrases = Set(
                    scenarios.map {
                        $0.voicePhrase.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).lowercased()
                    }.filter { !$0.isEmpty }
                )
                let importedPhrase = copy.voicePhrase.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).lowercased()
                if !importedPhrase.isEmpty,
                   phrases.contains(importedPhrase) {
                    copy.voicePhrase = ""
                    adjustedCount += 1
                }

                let hotKeys = Set(
                    scenarios.map(\.hotKey)
                        .filter(\.isEnabled)
                        .map(\.displayName)
                )
                if copy.hotKey.isEnabled,
                   hotKeys.contains(copy.hotKey.displayName) {
                    copy.hotKey = ScenarioHotKey()
                    adjustedCount += 1
                }

                scenarios.append(copy)
                imported.append(copy)
            }

            selectedID = imported.first?.id
            selectedWindowID = imported.first?.windows.first?.id
            transferError = nil
            transferMessage = "Imported \(imported.count) Cue\(imported.count == 1 ? "" : "s") · press Save Cues"
            if adjustedCount > 0 {
                transferMessage += " · conflicting activations were disabled"
            }
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func exportSelectedCue() {
        guard let selectedIndex else {
            return
        }
        let cue = scenarios[selectedIndex]
        let panel = NSSavePanel()
        panel.title = "Export PaneCue Cue"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue =
            sanitizedFileName(cue.name) + ".panecuecue.json"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try CueArchive(cues: [cue]).encodedData()
            try data.write(to: url, options: .atomic)
            transferError = nil
            transferMessage = "Exported “\(cue.name)”"
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        let components = value.components(separatedBy: invalid)
            .filter { !$0.isEmpty }
        let result = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "PaneCue-Cue" : result
    }

    private static func isValidWebURL(_ value: String) -> Bool {
        let candidate = value.contains("://")
            ? value
            : "https://\(value)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return url.host != nil
    }
}

private enum CueTransferError: LocalizedError {
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The selected Cue file is larger than 2 MB."
        }
    }
}

private struct ScenarioGridEditor: View {
    @Binding var windows: [ScenarioWindowSlot]
    @Binding var selectedWindowID: UUID?
    var canvasHeight: CGFloat = 360
    var onExpand: (() -> Void)?
    @State private var display: ScenarioDisplayTarget = .main

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Display", selection: $display) {
                    ForEach(ScenarioDisplayTarget.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 330)

                Spacer()

                Menu("Layout preset") {
                    Button("Equal columns") {
                        Self.applyColumnsPreset(to: &windows)
                    }
                    Button("Focus + stack") {
                        Self.applyFocusPreset(to: &windows)
                    }
                    Button("Balanced grid") {
                        Self.applyGridPreset(to: &windows)
                    }
                }

                if let onExpand {
                    Button(action: onExpand) {
                        Image(
                            systemName: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help("Open Large Layout Editor")
                }
            }

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.055))

                    GridLines()
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    ForEach($windows) { $window in
                        if window.display == display {
                            MovableGridSlot(
                                number: number(for: window.id),
                                name: window.target.displayName,
                                areaSize: geometry.size,
                                rect: $window.gridRect,
                                isSelected: selectedWindowID == window.id,
                                onSelect: {
                                    selectedWindowID = window.id
                                }
                            )
                        }
                    }

                    if !windows.contains(where: { $0.display == display }) {
                        VStack(spacing: 7) {
                            Image(systemName: "display")
                                .font(.title2)
                            Text("No windows on this display")
                                .font(.callout.weight(.medium))
                            Text(
                                "Select a window below and change its display."
                            )
                            .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator, lineWidth: 1)
                }
            }
            .frame(height: canvasHeight)

            Text(
                "Drag inside a window to move it. Resize from any side or corner. The layout snaps to the detailed 24 × 16 grid when you release."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func number(for id: UUID) -> Int {
        (windows.firstIndex { $0.id == id } ?? 0) + 1
    }

    static func applyColumnsPreset(
        to windows: inout [ScenarioWindowSlot]
    ) {
        let groups = Dictionary(grouping: windows.indices) {
            windows[$0].display
        }
        for indices in groups.values {
            let width = 1 / Double(indices.count)
            for (position, index) in indices.enumerated() {
                windows[index].gridRect = ScenarioGridRect(
                    x: Double(position) * width,
                    y: 0,
                    width: width,
                    height: 1
                )
            }
        }
    }

    static func applyFocusPreset(
        to windows: inout [ScenarioWindowSlot]
    ) {
        let groups = Dictionary(grouping: windows.indices) {
            windows[$0].display
        }
        for indices in groups.values {
            guard let first = indices.first else {
                continue
            }
            if indices.count == 1 {
                windows[first].gridRect = ScenarioGridRect(
                    x: 0,
                    y: 0,
                    width: 1,
                    height: 1
                )
                continue
            }
            windows[first].gridRect = ScenarioGridRect(
                x: 0,
                y: 0,
                width: 2.0 / 3.0,
                height: 1
            )
            let secondary = Array(indices.dropFirst())
            let height = 1 / Double(secondary.count)
            for (position, index) in secondary.enumerated() {
                windows[index].gridRect = ScenarioGridRect(
                    x: 2.0 / 3.0,
                    y: Double(position) * height,
                    width: 1.0 / 3.0,
                    height: height
                )
            }
        }
    }

    static func applyGridPreset(
        to windows: inout [ScenarioWindowSlot]
    ) {
        let groups = Dictionary(grouping: windows.indices) {
            windows[$0].display
        }
        for indices in groups.values {
            let columns = Int(ceil(sqrt(Double(indices.count))))
            let rows = Int(ceil(Double(indices.count) / Double(columns)))
            let width = 1 / Double(columns)
            let height = 1 / Double(rows)
            for (position, index) in indices.enumerated() {
                windows[index].gridRect = ScenarioGridRect(
                    x: Double(position % columns) * width,
                    y: Double(position / columns) * height,
                    width: width,
                    height: height
                )
            }
        }
    }
}

private struct ExpandedScenarioGridEditor: View {
    @Binding var scenario: CustomScenario
    @Binding var selectedWindowID: UUID?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Large Layout Editor")
                        .font(.title2.weight(.semibold))
                    Text(scenario.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScenarioGridEditor(
                windows: $scenario.windows,
                selectedWindowID: $selectedWindowID,
                canvasHeight: 520
            )
            .padding(20)
        }
        .frame(minWidth: 820, minHeight: 650)
    }
}

private struct GridLines: View {
    private let columns = ScenarioGridResolution.columns
    private let rows = ScenarioGridResolution.rows
    private let majorInterval = ScenarioGridResolution.majorLineInterval

    var body: some View {
        Canvas { context, size in
            var minorPath = Path()
            var majorPath = Path()

            for column in 1..<columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                if column.isMultiple(of: majorInterval) {
                    majorPath.move(to: CGPoint(x: x, y: 0))
                    majorPath.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    minorPath.move(to: CGPoint(x: x, y: 0))
                    minorPath.addLine(to: CGPoint(x: x, y: size.height))
                }
            }

            for row in 1..<rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                if row.isMultiple(of: majorInterval) {
                    majorPath.move(to: CGPoint(x: 0, y: y))
                    majorPath.addLine(to: CGPoint(x: size.width, y: y))
                } else {
                    minorPath.move(to: CGPoint(x: 0, y: y))
                    minorPath.addLine(to: CGPoint(x: size.width, y: y))
                }
            }

            context.stroke(
                minorPath,
                with: .color(.secondary.opacity(0.07)),
                lineWidth: 0.5
            )
            context.stroke(
                majorPath,
                with: .color(.secondary.opacity(0.14)),
                lineWidth: 1
            )

            for column in 1..<columns {
                for row in 1..<rows {
                    let x = size.width * CGFloat(column)
                        / CGFloat(columns)
                    let y = size.height * CGFloat(row) / CGFloat(rows)
                    let isMajor = column.isMultiple(of: majorInterval)
                        && row.isMultiple(of: majorInterval)
                    let diameter: CGFloat = isMajor ? 2.2 : 1.2
                    let dotRect = CGRect(
                        x: x - diameter / 2,
                        y: y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(
                            .secondary.opacity(isMajor ? 0.3 : 0.18)
                        )
                    )
                }
            }
        }
    }
}

private struct MovableGridSlot: View {
    let number: Int
    let name: String
    let areaSize: CGSize
    @Binding var rect: ScenarioGridRect
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var moveStart: ScenarioGridRect?
    @State private var resizeStart: ScenarioGridRect?
    @State private var activeResizeHandle: ScenarioGridResizeHandle?
    @State private var previewRect: ScenarioGridRect?

    var body: some View {
        let displayedRect = previewRect ?? rect

        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    Color.accentColor.opacity(isSelected ? 0.3 : 0.16)
                )
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Text("\(number)")
                            .font(.caption2.bold().monospacedDigit())
                            .frame(width: 19, height: 19)
                            .background(Circle().fill(Color.accentColor))
                            .foregroundStyle(.white)
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            Color.accentColor.opacity(
                                isSelected ? 0.9 : 0.38
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .gesture(moveGesture)

            if isSelected {
                GeometryReader { geometry in
                    ForEach(
                        ScenarioGridResizeHandle.allCases,
                        id: \.self
                    ) { handle in
                        resizeHandle(handle)
                            .position(
                                handlePosition(
                                    for: handle,
                                    in: geometry.size
                                )
                            )
                    }
                }
            }
        }
        .frame(
            width: max(areaSize.width * displayedRect.width, 34),
            height: max(areaSize.height * displayedRect.height, 28)
        )
        .position(
            x: areaSize.width
                * (displayedRect.x + displayedRect.width / 2),
            y: areaSize.height
                * (displayedRect.y + displayedRect.height / 2)
        )
        .zIndex(isSelected ? 10 : 0)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveStart == nil {
                    moveStart = rect
                    previewRect = rect
                    onSelect()
                }
                guard let start = moveStart,
                      areaSize.width > 0,
                      areaSize.height > 0 else {
                    return
                }
                previewRect = ScenarioGridInteraction.movedRect(
                    from: start,
                    translation: value.translation,
                    canvasSize: areaSize
                )
            }
            .onEnded { value in
                if let start = moveStart {
                    let finalPreview = ScenarioGridInteraction.movedRect(
                        from: start,
                        translation: value.translation,
                        canvasSize: areaSize
                    )
                    rect = ScenarioGridInteraction.snappedMovedRect(
                        finalPreview
                    )
                }
                moveStart = nil
                previewRect = nil
            }
    }

    private func resizeGesture(
        for handle: ScenarioGridResizeHandle
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeHandle == nil {
                    resizeStart = rect
                    activeResizeHandle = handle
                    previewRect = rect
                    onSelect()
                }
                guard activeResizeHandle == handle,
                      let start = resizeStart,
                      areaSize.width > 0,
                      areaSize.height > 0 else {
                    return
                }
                previewRect = ScenarioGridInteraction.resizedRect(
                    from: start,
                    handle: handle,
                    translation: value.translation,
                    canvasSize: areaSize
                )
            }
            .onEnded { value in
                if activeResizeHandle == handle,
                   let start = resizeStart {
                    let finalPreview = ScenarioGridInteraction.resizedRect(
                        from: start,
                        handle: handle,
                        translation: value.translation,
                        canvasSize: areaSize
                    )
                    rect = ScenarioGridInteraction.snappedResizedRect(
                        finalPreview,
                        handle: handle
                    )
                }
                resizeStart = nil
                activeResizeHandle = nil
                previewRect = nil
            }
    }

    private func resizeHandle(
        _ handle: ScenarioGridResizeHandle
    ) -> some View {
        ZStack {
            Color.clear
            handleShape(handle)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .highPriorityGesture(resizeGesture(for: handle))
        .help(handle.helpText)
    }

    @ViewBuilder
    private func handleShape(
        _ handle: ScenarioGridResizeHandle
    ) -> some View {
        switch handle {
        case .top, .bottom:
            Capsule()
                .frame(width: 22, height: 5)
        case .leading, .trailing:
            Capsule()
                .frame(width: 5, height: 22)
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            Circle()
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
        }
    }

    private func handlePosition(
        for handle: ScenarioGridResizeHandle,
        in size: CGSize
    ) -> CGPoint {
        let inset = min(11, size.width / 2, size.height / 2)
        let minimumX = inset
        let maximumX = max(size.width - inset, inset)
        let minimumY = inset
        let maximumY = max(size.height - inset, inset)

        switch handle {
        case .topLeading:
            return CGPoint(x: minimumX, y: minimumY)
        case .top:
            return CGPoint(x: size.width / 2, y: minimumY)
        case .topTrailing:
            return CGPoint(x: maximumX, y: minimumY)
        case .trailing:
            return CGPoint(x: maximumX, y: size.height / 2)
        case .bottomTrailing:
            return CGPoint(x: maximumX, y: maximumY)
        case .bottom:
            return CGPoint(x: size.width / 2, y: maximumY)
        case .bottomLeading:
            return CGPoint(x: minimumX, y: maximumY)
        case .leading:
            return CGPoint(x: minimumX, y: size.height / 2)
        }
    }
}

private extension ScenarioGridResizeHandle {
    var helpText: String {
        switch self {
        case .topLeading:
            return "Resize from Top Left"
        case .top:
            return "Resize from Top"
        case .topTrailing:
            return "Resize from Top Right"
        case .trailing:
            return "Resize from Right"
        case .bottomTrailing:
            return "Resize from Bottom Right"
        case .bottom:
            return "Resize from Bottom"
        case .bottomLeading:
            return "Resize from Bottom Left"
        case .leading:
            return "Resize from Left"
        }
    }
}
