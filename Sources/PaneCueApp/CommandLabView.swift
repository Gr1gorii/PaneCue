import AppKit
import PaneCueCore
import SwiftUI

struct CommandLabView: View {
    @ObservedObject var model: PaneCueDashboardModel

    @State private var transcript = ""
    @State private var analyzedIntent: VoiceCommandIntent?
    @State private var workspacePlan: WorkspacePlan?
    @State private var planHistory: [WorkspacePlan] = []
    @State private var lastAnalyzedTranscript = ""
    @State private var hasAnalyzed = false
    @State private var isAnalyzing = false
    @State private var isApplying = false
    @State private var isListening = false
    @State private var feedback = ""
    @State private var errorMessage: String?
    @State private var applyResult: WorkspaceApplyResult?
    @State private var didRollback = false
    @State private var isSelectingCandidate = false
    @State private var isRefreshingCandidates = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                commandInput

                if hasAnalyzed {
                    analysisContent
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 34)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .onDisappear {
            if isListening {
                model.cancelCommandLabListening()
                isListening = false
            }
            model.discardArrangementPreview()
        }
        .onAppear {
            adoptExternalPreview()
        }
        .onChange(of: model.arrangementEditorSeed?.id) { _, _ in
            adoptExternalPreview()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.indigo.gradient)
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text("Arrange")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(
                    "Describe your workspace in Russian or English. Nothing moves until you approve the preview."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                "Local only",
                systemImage: "lock.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color.green.opacity(0.11),
                in: Capsule()
            )
        }
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Command")
                    .font(.headline)
                Spacer()
                Text("Russian or English")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $transcript)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 82, maxHeight: 112)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1))
                }

            HStack(spacing: 10) {
                if isListening {
                    Button {
                        toggleListening()
                    } label: {
                        Label(
                            "Stop & Transcribe",
                            systemImage: "stop.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isAnalyzing || isApplying)
                } else if PaneCueReleaseProfile.current.isExperimental
                    || model.hasCompletedTextOnboarding {
                    Button {
                        toggleListening()
                    } label: {
                        Label("Speak", systemImage: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing || isApplying)
                }

                Spacer()

                if !transcript.isEmpty {
                    Button("Clear") {
                        transcript = ""
                        analyzedIntent = nil
                        workspacePlan = nil
                        planHistory = []
                        lastAnalyzedTranscript = ""
                        hasAnalyzed = false
                        feedback = ""
                        errorMessage = nil
                        applyResult = nil
                        didRollback = false
                        model.discardArrangementPreview()
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    analyze()
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            "Create Preview",
                            systemImage: "sparkles"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(
                    transcript.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || isAnalyzing || isListening
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    @ViewBuilder
    private var analysisContent: some View {
        if let workspacePlan {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionHeader(
                            "Preview",
                            detail: "Drag a window or resize it from any side or corner."
                        )
                        Spacer()
                        if !planHistory.isEmpty {
                            Button {
                                undoPlanChange()
                            } label: {
                                Label(
                                    "Undo",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    CommandLabPlanCanvas(
                        plan: Binding(
                            get: {
                                self.workspacePlan ?? workspacePlan
                            },
                            set: {
                                self.workspacePlan = $0
                                self.applyResult = nil
                                self.didRollback = false
                            }
                        ),
                        resolution: candidatePreview(
                            for: workspacePlan
                        )?.resolution,
                        onCommit: { previous in
                            remember(previous)
                            feedback = "Preview updated"
                            refreshResolutionIfTargetsChanged(
                                from: previous
                            )
                        }
                    )
                    .frame(minHeight: 350)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                CommandLabPlanInspector(
                    plan: Binding(
                        get: {
                            self.workspacePlan ?? workspacePlan
                        },
                            set: {
                                self.workspacePlan = $0
                                self.applyResult = nil
                                self.didRollback = false
                            }
                    ),
                    resolution: candidatePreview(
                        for: workspacePlan
                    )?.resolution,
                    applications: model.applications,
                    canUndo: !planHistory.isEmpty,
                    onBeginChange: { previous in
                        remember(previous)
                        refreshResolutionIfTargetsChanged(
                            from: previous
                        )
                    },
                    onUndo: {
                        undoPlanChange()
                    },
                    onSaveCorrection: {
                        guard let current = self.workspacePlan else {
                            return
                        }
                        model.savePlanCorrection(
                            transcript: lastAnalyzedTranscript,
                            plan: current
                        )
                        feedback = "Correction saved locally"
                    },
                    onSaveScenario: { name in
                        guard let current = self.workspacePlan else {
                            return
                        }
                        feedback = try model.saveWorkspacePlan(
                            current,
                            name: name
                        )
                    },
                    onMarkNoAction: {
                        model.saveCommandCorrection(
                            transcript: lastAnalyzedTranscript,
                            intent: nil
                        )
                        self.workspacePlan = nil
                        self.analyzedIntent = nil
                        self.planHistory = []
                        feedback = "Saved as No Action"
                        model.discardArrangementPreview()
                    }
                )
                .frame(width: 315)
            }

            if let preview = candidatePreview(for: workspacePlan),
               let resolution = preview.resolution,
               resolution.slots.contains(where: {
                   !$0.candidates.isEmpty
                       && (
                           $0.candidates.count > 1
                               || isAmbiguous($0.state)
                       )
               }) {
                ArrangementCandidateChooser(
                    plan: workspacePlan,
                    resolution: resolution,
                    isSelecting: isSelectingCandidate
                        || isRefreshingCandidates,
                    onSelect: { slotID, candidateID in
                        selectCandidate(
                            previewID: preview.id,
                            slotID: slotID,
                            candidateID: candidateID
                        )
                    }
                )
            }

            if let applyResult {
                WorkspaceApplyResultCard(
                    result: applyResult,
                    didRollback: didRollback,
                    isRollingBack: isApplying,
                    onRollback: rollbackApply
                )
            }

            HStack(spacing: 12) {
                if !feedback.isEmpty {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                Button("Discard Draft") {
                    self.workspacePlan = nil
                    self.analyzedIntent = nil
                    planHistory = []
                    hasAnalyzed = false
                    feedback = ""
                    applyResult = nil
                    didRollback = false
                    model.discardArrangementPreview()
                }
                .buttonStyle(.bordered)

                Button {
                    applyPlan()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            "Apply \(workspacePlan.windows.count) Windows",
                            systemImage: "play.fill"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isApplying
                        || isSelectingCandidate
                        || isRefreshingCandidates
                        || workspacePlan.windows.count < 2
                        || candidatePreview(for: workspacePlan)?
                            .eligibility != .ready
                )
            }
        } else if let analyzedIntent {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(
                        "Layout Preview",
                        detail: "The proposed screen arrangement."
                    )
                    CommandLabLayoutPreview(
                        intent: analyzedIntent,
                        scenarios: model.scenarios
                    )
                    .frame(minHeight: 285)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                CommandLabInspector(
                    intent: Binding(
                        get: { self.analyzedIntent ?? analyzedIntent },
                        set: { self.analyzedIntent = $0 }
                    ),
                    applications: model.applications,
                    onSave: {
                        guard let current = self.analyzedIntent else {
                            return
                        }
                        model.saveCommandCorrection(
                            transcript: transcript,
                            intent: current
                        )
                        feedback = "Correction saved locally"
                    },
                    onMarkNoAction: {
                        model.saveCommandCorrection(
                            transcript: transcript,
                            intent: nil
                        )
                        self.analyzedIntent = nil
                        feedback = "Saved as No Action"
                        model.discardArrangementPreview()
                    }
                )
                .frame(width: 300)
            }

            HStack(spacing: 12) {
                if !feedback.isEmpty {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                Button("Cancel") {
                    self.analyzedIntent = nil
                    self.workspacePlan = nil
                    hasAnalyzed = false
                    feedback = ""
                    applyResult = nil
                    didRollback = false
                    model.discardArrangementPreview()
                }
                .buttonStyle(.bordered)

                Button {
                    apply()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            "Apply Layout",
                            systemImage: "play.fill"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
            }
        } else {
            noActionResult
        }
    }

    private var noActionResult: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 31))
                .foregroundStyle(.secondary)
            Text("No safe PaneCue action found")
                .font(.title3.weight(.semibold))
            Text(
                "The command may be unrelated, ambiguous, phrased as a question, or explicitly negated. No windows were changed."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)

            HStack {
                Button("Try Another Command") {
                    hasAnalyzed = false
                    feedback = ""
                }
                .buttonStyle(.bordered)

                Button("Remember as No Action") {
                    model.saveCommandCorrection(
                        transcript: transcript,
                        intent: nil
                    )
                    feedback = "Saved locally"
                }
                .buttonStyle(.borderedProminent)
            }

            if !feedback.isEmpty {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                model.hasCompletedTextOnboarding
                    ? "Try a command"
                    : "Start with a text command"
            )
                .font(.headline)
            Text(
                model.hasCompletedTextOnboarding
                    ? "“Open VS Code, Notes and Terminal”\n“Make Notes even smaller”\n“Add Terminal at the bottom”\n“Save this as Development”"
                    : "Type “Open VS Code, Notes and Terminal”, review the preview, then press Apply. Voice remains optional and becomes available after the first successful arrangement."
            )
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .lineSpacing(6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.indigo.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func sectionHeader(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func analyze() {
        isAnalyzing = true
        errorMessage = nil
        feedback = ""
        applyResult = nil
        didRollback = false
        Task { @MainActor in
            defer {
                isAnalyzing = false
            }
            do {
                let command = transcript.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let result = try await model.analyzeCommand(
                    command,
                    currentPlan: workspacePlan
                )
                lastAnalyzedTranscript = command
                switch result {
                case let .plan(plan, summary):
                    if let previous = workspacePlan,
                       previous != plan {
                        remember(previous)
                    }
                    workspacePlan = plan
                    analyzedIntent = nil
                    hasAnalyzed = true
                    feedback = summary
                case let .action(intent):
                    workspacePlan = nil
                    planHistory = []
                    analyzedIntent = intent
                    hasAnalyzed = true
                case .undo:
                    if planHistory.isEmpty {
                        feedback = "Nothing to undo yet"
                    } else {
                        undoPlanChange()
                    }
                case let .savePlan(name):
                    guard let workspacePlan else {
                        feedback = "Create a workspace plan first"
                        return
                    }
                    feedback = try model.saveWorkspacePlan(
                        workspacePlan,
                        name: name
                    )
                case .noAction:
                    if workspacePlan != nil {
                        feedback = "No safe change found — draft kept"
                    } else {
                        analyzedIntent = nil
                        hasAnalyzed = true
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func adoptExternalPreview() {
        guard let preview = model.arrangementEditorSeed else {
            return
        }
        transcript = ""
        lastAnalyzedTranscript = ""
        analyzedIntent = nil
        workspacePlan = preview.plan
        planHistory = []
        hasAnalyzed = true
        isAnalyzing = false
        isApplying = false
        feedback = "Opened from Quick Cue"
        errorMessage = nil
        applyResult = nil
        didRollback = false
        model.consumeArrangementEditorSeed(preview.id)
    }

    private func toggleListening() {
        errorMessage = nil
        Task { @MainActor in
            do {
                if isListening {
                    transcript = try await model
                        .stopCommandLabListening()
                    isListening = false
                    analyze()
                } else {
                    try await model.startCommandLabListening()
                    isListening = true
                }
            } catch {
                model.cancelCommandLabListening()
                isListening = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply() {
        guard let analyzedIntent else {
            return
        }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                isApplying = false
            }
            do {
                feedback = try await model.applyAnalyzedCommand(
                    analyzedIntent
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyPlan() {
        guard let workspacePlan else {
            return
        }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                isApplying = false
            }
            do {
                let result = try await model.applyWorkspacePlan(
                    workspacePlan
                )
                applyResult = result
                didRollback = false
                feedback = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rollbackApply() {
        guard applyResult?.canRollback == true, !didRollback else {
            return
        }
        isApplying = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                isApplying = false
            }
            do {
                feedback = try await model.rollbackLastApply()
                didRollback = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remember(_ plan: WorkspacePlan) {
        guard planHistory.last != plan else {
            return
        }
        planHistory.append(plan)
        if planHistory.count > 30 {
            planHistory.removeFirst(planHistory.count - 30)
        }
    }

    private func undoPlanChange() {
        guard let previous = planHistory.popLast() else {
            return
        }
        let current = workspacePlan
        workspacePlan = previous
        analyzedIntent = nil
        hasAnalyzed = true
        feedback = "Undid the last draft change"
        applyResult = nil
        didRollback = false
        if let current,
           !targetsMatch(current, previous) {
            refreshResolution(for: previous)
        }
    }

    private func candidatePreview(
        for plan: WorkspacePlan
    ) -> ArrangementPreview? {
        guard let preview = model.arrangementPreview,
              preview.id == plan.id else {
            return nil
        }
        return preview
    }

    private func isAmbiguous(
        _ state: ArrangementTargetResolutionState
    ) -> Bool {
        if case .ambiguous = state {
            return true
        }
        return false
    }

    private func refreshResolutionIfTargetsChanged(
        from previous: WorkspacePlan
    ) {
        guard let current = workspacePlan,
              !targetsMatch(previous, current) else {
            return
        }
        refreshResolution(for: current)
    }

    private func refreshResolution(for plan: WorkspacePlan) {
        isRefreshingCandidates = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                isRefreshingCandidates = false
            }
            do {
                try await model.prepareWorkspacePlan(plan)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectCandidate(
        previewID: UUID,
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) {
        isSelectingCandidate = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                isSelectingCandidate = false
            }
            do {
                try await model.selectArrangementCandidate(
                    previewID: previewID,
                    slotID: slotID,
                    candidateID: candidateID
                )
                feedback = "Window selected"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func targetsMatch(
        _ first: WorkspacePlan,
        _ second: WorkspacePlan
    ) -> Bool {
        guard first.windows.count == second.windows.count else {
            return false
        }
        return zip(first.windows, second.windows).allSatisfy { lhs, rhs in
            lhs.id == rhs.id
                && lhs.target == rhs.target
                && lhs.display == rhs.display
        }
    }
}

private struct ArrangementCandidateChooser: View {
    let plan: WorkspacePlan
    let resolution: ArrangementTargetResolutionSet
    let isSelecting: Bool
    let onSelect: (UUID, EphemeralWindowIdentifier) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose the exact window")
                        .font(.headline)
                    Text(
                        "PaneCue found more than one match. Apply stays disabled until every required choice is resolved."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(chooserSlots) { slot in
                candidateSection(slot)
            }
        }
        .padding(18)
        .background(
            Color.orange.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.orange.opacity(0.28))
        }
    }

    private var chooserSlots: [ArrangementSlotResolution] {
        resolution.slots.filter {
            !$0.candidates.isEmpty
                && ($0.candidates.count > 1 || isAmbiguous($0.state))
        }
    }

    @ViewBuilder
    private func candidateSection(
        _ slot: ArrangementSlotResolution
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(targetName(for: slot.id))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isAmbiguous(slot.state) {
                    Label(
                        "Needs selection",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(.orange)
                } else if let reason = matchReason(for: slot.state) {
                    Label(
                        reason.shortDescription,
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            ForEach(Array(slot.candidates.enumerated()), id: \.element.id) {
                index, candidate in
                candidateButton(
                    candidate,
                    index: index,
                    slot: slot,
                    shortcutNumber: shortcutNumber(
                        slotID: slot.id,
                        candidateID: candidate.id
                    )
                )
            }
        }
        .padding(13)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }

    @ViewBuilder
    private func candidateButton(
        _ candidate: ArrangementTargetCandidate,
        index: Int,
        slot: ArrangementSlotResolution,
        shortcutNumber: Int?
    ) -> some View {
        let selected = selectedCandidateID(for: slot.state) == candidate.id
        let button = Button {
            onSelect(slot.id, candidate.id)
        } label: {
            HStack(spacing: 11) {
                applicationIcon(for: candidate)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.localizedApplicationName)
                        .font(.subheadline.weight(.medium))
                    Text(
                        candidate.localDifferentiator
                            ?? "Window \(index + 1)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                if let shortcutNumber, !selected {
                    Text("⌘\(shortcutNumber)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                } else if !candidate.isSelectable {
                    Text("Unavailable")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                selected
                    ? Color.indigo.opacity(0.14)
                    : Color(nsColor: .controlBackgroundColor).opacity(0.55),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        selected
                            ? Color.indigo.opacity(0.65)
                            : Color.primary.opacity(0.08)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting || selected || !candidate.isSelectable)
        .accessibilityLabel(
            "\(candidate.localizedApplicationName), \(candidate.localDifferentiator ?? "Window \(index + 1)")"
        )
        .accessibilityHint(
            selected
                ? "Selected for this Preview slot"
                : "Select this window for the Preview slot"
        )

        if let shortcutNumber {
            button.keyboardShortcut(
                KeyEquivalent(Character(String(shortcutNumber))),
                modifiers: .command
            )
        } else {
            button
        }
    }

    @ViewBuilder
    private func applicationIcon(
        for candidate: ArrangementTargetCandidate
    ) -> some View {
        if let bundleIdentifier = candidate.bundleIdentifier,
           let icon = NSRunningApplication.runningApplications(
               withBundleIdentifier: bundleIdentifier
           ).first?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "macwindow")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func targetName(for slotID: UUID) -> String {
        plan.windows.first(where: { $0.id == slotID })?
            .target.displayName ?? "Window"
    }

    private func shortcutNumber(
        slotID: UUID,
        candidateID: EphemeralWindowIdentifier
    ) -> Int? {
        let ordered = chooserSlots.flatMap { slot in
            slot.candidates.filter(\.isSelectable).map {
                (slot.id, $0.id)
            }
        }
        guard let index = ordered.firstIndex(where: {
            $0.0 == slotID && $0.1 == candidateID
        }), index < 9 else {
            return nil
        }
        return index + 1
    }

    private func selectedCandidateID(
        for state: ArrangementTargetResolutionState
    ) -> EphemeralWindowIdentifier? {
        guard case let .resolved(target) = state else {
            return nil
        }
        return target.windowIdentifier
    }

    private func isAmbiguous(
        _ state: ArrangementTargetResolutionState
    ) -> Bool {
        if case .ambiguous = state {
            return true
        }
        return false
    }

    private func matchReason(
        for state: ArrangementTargetResolutionState
    ) -> ArrangementTargetMatchReason? {
        guard case let .resolved(target) = state else {
            return nil
        }
        return target.matchReason
    }
}

private struct WorkspaceApplyResultCard: View {
    let result: WorkspaceApplyResult
    let didRollback: Bool
    let isRollingBack: Bool
    let onRollback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Label(result.summary, systemImage: summaryIcon)
                    .font(.headline)
                    .foregroundStyle(summaryColor)

                Spacer()

                if didRollback {
                    Label(
                        "Layout restored",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                } else if result.canRollback {
                    Button(action: onRollback) {
                        Label(
                            result.isPartial ? "Rollback" : "Undo Apply",
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRollingBack)
                }
            }

            Divider()

            VStack(spacing: 9) {
                ForEach(result.outcomes) { outcome in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: outcome.status.icon)
                            .foregroundStyle(outcome.status.color)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.applicationName ?? outcome.targetName)
                                .font(.callout.weight(.semibold))
                            if let reason = outcome.reason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer()

                        Text(outcome.status.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(outcome.status.color)
                    }
                }
            }
        }
        .padding(16)
        .background(
            summaryColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(summaryColor.opacity(0.22))
        }
    }

    private var summaryIcon: String {
        if result.failedCount > 0 || result.skippedCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        return result.didChangeAnyWindow
            ? "checkmark.circle.fill"
            : "minus.circle.fill"
    }

    private var summaryColor: Color {
        if result.failedCount > 0 {
            return .red
        }
        if result.skippedCount > 0 {
            return .orange
        }
        return result.didChangeAnyWindow ? .green : .secondary
    }
}

private extension WorkspaceApplyOutcomeStatus {
    var title: String {
        switch self {
        case .moved:
            return "Moved"
        case .unchanged:
            return "Unchanged"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .moved:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .skipped:
            return "forward.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .moved:
            return .green
        case .unchanged:
            return .secondary
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }
}

private struct CommandLabInspector: View {
    @Binding var intent: VoiceCommandIntent
    let applications: [InstalledApplication]
    let onSave: () -> Void
    let onMarkNoAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Interpretation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(
                    intent.action.commandLabTitle,
                    systemImage: intent.action.commandLabIcon
                )
                .font(.headline)
            }

            Divider()

            if intent.action == .arrangeDynamicWorkspace {
                dynamicControls
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(intent.action.commandLabDetail)
                        .font(.callout)
                }
            }

            Spacer(minLength: 8)

            Button {
                onSave()
            } label: {
                Label(
                    "Save Correction",
                    systemImage: "brain.head.profile"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onMarkNoAction()
            } label: {
                Label(
                    "This Should Do Nothing",
                    systemImage: "hand.raised"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(minHeight: 350, alignment: .top)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 17)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var dynamicControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            targetPicker(
                title: "Primary window",
                prefix: "primary"
            )
            targetPicker(
                title: "Secondary window",
                prefix: "secondary"
            )

            Button {
                swapTargets()
            } label: {
                Label("Swap Windows", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Primary size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "\(Int((primaryRatio * 100).rounded()))%"
                    )
                    .font(.caption.monospacedDigit().weight(.semibold))
                }
                Slider(
                    value: Binding(
                        get: { primaryRatio },
                        set: { setPrimaryRatio($0) }
                    ),
                    in: 0.5...0.8,
                    step: 0.01
                )
            }

            Picker(
                "Direction",
                selection: argumentBinding(
                    DynamicWorkspaceArgument.axis,
                    fallback: "horizontal"
                )
            ) {
                Text("Side by side").tag("horizontal")
                Text("Stacked").tag("vertical")
            }
            .pickerStyle(.segmented)

            Picker(
                "Primary position",
                selection: argumentBinding(
                    DynamicWorkspaceArgument.primaryPosition,
                    fallback: "leading"
                )
            ) {
                Text(primaryPositionLeadingTitle).tag("leading")
                Text(primaryPositionTrailingTitle).tag("trailing")
            }
            .pickerStyle(.segmented)
        }
    }

    private var primaryRatio: Double {
        Double(
            intent.arguments[
                DynamicWorkspaceArgument.primaryRatio
            ] ?? "0.65"
        ) ?? 0.65
    }

    private var primaryPositionLeadingTitle: String {
        intent.arguments[DynamicWorkspaceArgument.axis]
            == "vertical" ? "Top" : "Left"
    }

    private var primaryPositionTrailingTitle: String {
        intent.arguments[DynamicWorkspaceArgument.axis]
            == "vertical" ? "Bottom" : "Right"
    }

    private func targetPicker(
        title: String,
        prefix: String
    ) -> some View {
        Picker(
            title,
            selection: targetBinding(prefix: prefix)
        ) {
            Section("Roles") {
                ForEach(CommandLabTargetOption.roles) { option in
                    Text(option.name).tag(option.id)
                }
            }
            Section("Applications") {
                ForEach(applicationOptions) { option in
                    Text(option.name).tag(option.id)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var applicationOptions: [CommandLabTargetOption] {
        applications.map {
            CommandLabTargetOption(
                kind: "application",
                value: $0.bundleIdentifier,
                name: $0.displayName
            )
        }
    }

    private func targetBinding(
        prefix: String
    ) -> Binding<String> {
        Binding(
            get: {
                let kindKey = prefix == "primary"
                    ? DynamicWorkspaceArgument.primaryKind
                    : DynamicWorkspaceArgument.secondaryKind
                let valueKey = prefix == "primary"
                    ? DynamicWorkspaceArgument.primaryValue
                    : DynamicWorkspaceArgument.secondaryValue
                return CommandLabTargetOption.id(
                    kind: intent.arguments[kindKey] ?? "role",
                    value: intent.arguments[valueKey] ?? "other"
                )
            },
            set: { id in
                let options = CommandLabTargetOption.roles
                    + applicationOptions
                guard let option = options.first(where: {
                    $0.id == id
                }) else {
                    return
                }
                setTarget(option, prefix: prefix)
            }
        )
    }

    private func setTarget(
        _ option: CommandLabTargetOption,
        prefix: String
    ) {
        let kindKey = prefix == "primary"
            ? DynamicWorkspaceArgument.primaryKind
            : DynamicWorkspaceArgument.secondaryKind
        let valueKey = prefix == "primary"
            ? DynamicWorkspaceArgument.primaryValue
            : DynamicWorkspaceArgument.secondaryValue
        let nameKey = prefix == "primary"
            ? DynamicWorkspaceArgument.primaryName
            : DynamicWorkspaceArgument.secondaryName
        intent.arguments[kindKey] = option.kind
        intent.arguments[valueKey] = option.value
        intent.arguments[nameKey] = option.name
    }

    private func swapTargets() {
        let pairs = [
            (
                DynamicWorkspaceArgument.primaryKind,
                DynamicWorkspaceArgument.secondaryKind
            ),
            (
                DynamicWorkspaceArgument.primaryValue,
                DynamicWorkspaceArgument.secondaryValue
            ),
            (
                DynamicWorkspaceArgument.primaryName,
                DynamicWorkspaceArgument.secondaryName
            )
        ]
        for pair in pairs {
            let left = intent.arguments[pair.0]
            intent.arguments[pair.0] = intent.arguments[pair.1]
            intent.arguments[pair.1] = left
        }
    }

    private func setPrimaryRatio(_ ratio: Double) {
        intent.arguments[
            DynamicWorkspaceArgument.primaryRatio
        ] = String(format: "%.2f", ratio)
    }

    private func argumentBinding(
        _ key: String,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: { intent.arguments[key] ?? fallback },
            set: { intent.arguments[key] = $0 }
        )
    }
}

private struct CommandLabTargetOption: Identifiable {
    let kind: String
    let value: String
    let name: String

    var id: String {
        Self.id(kind: kind, value: value)
    }

    static let roles = ApplicationRole.allCases
        .filter { $0 != .other }
        .map {
            CommandLabTargetOption(
                kind: "role",
                value: $0.rawValue,
                name: $0.displayName
            )
        }

    static func id(kind: String, value: String) -> String {
        "\(kind)|\(value)"
    }
}

private struct CommandLabLayoutPreview: View {
    let intent: VoiceCommandIntent
    let scenarios: [CustomScenario]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.72))

                ForEach(items) { item in
                    RoundedRectangle(cornerRadius: 11)
                        .fill(item.color.opacity(0.72))
                        .overlay {
                            VStack(spacing: 5) {
                                Image(systemName: item.systemImage)
                                Text(item.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(.white.opacity(0.2))
                        }
                        .frame(
                            width: max(
                                44,
                                proxy.size.width * item.rect.width - 8
                            ),
                            height: max(
                                40,
                                proxy.size.height * item.rect.height - 8
                            )
                        )
                        .position(
                            x: proxy.size.width
                                * (
                                    item.rect.minX
                                        + item.rect.width / 2
                                ),
                            y: proxy.size.height
                                * (
                                    item.rect.minY
                                        + item.rect.height / 2
                                )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.12))
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
    }

    private var items: [CommandLabPreviewItem] {
        switch intent.action {
        case .applyCodeAndCall:
            return [
                item(
                    "Code Editor",
                    rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    color: .indigo,
                    icon: "chevron.left.forwardslash.chevron.right"
                ),
                item(
                    "Call",
                    rect: CGRect(
                        x: 0.72,
                        y: 0.05,
                        width: 0.25,
                        height: 0.28
                    ),
                    color: .purple,
                    icon: "video.fill"
                )
            ]
        case .applyDocumentationAndCode:
            return pair(
                primary: "Code",
                secondary: "Documentation",
                ratio: 0.65
            )
        case .applyNotesAndBrowser:
            return pair(
                primary: "Browser",
                secondary: "Notes",
                ratio: 0.65
            )
        case .showBrowserVideo:
            return [
                item(
                    "Browser Video",
                    rect: CGRect(
                        x: 0.18,
                        y: 0.22,
                        width: 0.64,
                        height: 0.56
                    ),
                    color: .pink,
                    icon: "play.fill"
                )
            ]
        case .arrangeDynamicWorkspace:
            return dynamicItems
        case .applyCustomScenario:
            return customItems
        case .restorePreviousLayout:
            return []
        }
    }

    private var dynamicItems: [CommandLabPreviewItem] {
        let ratio = min(
            max(
                Double(
                    intent.arguments[
                        DynamicWorkspaceArgument.primaryRatio
                    ] ?? "0.65"
                ) ?? 0.65,
                0.5
            ),
            0.8
        )
        let vertical =
            intent.arguments[DynamicWorkspaceArgument.axis]
                == "vertical"
        let leads =
            intent.arguments[
                DynamicWorkspaceArgument.primaryPosition
            ] != "trailing"
        let primaryName =
            intent.arguments[DynamicWorkspaceArgument.primaryName]
                ?? "Primary"
        let secondaryName =
            intent.arguments[DynamicWorkspaceArgument.secondaryName]
                ?? "Secondary"

        let primaryRect: CGRect
        let secondaryRect: CGRect
        if vertical {
            primaryRect = CGRect(
                x: 0,
                y: leads ? 0 : 1 - ratio,
                width: 1,
                height: ratio
            )
            secondaryRect = CGRect(
                x: 0,
                y: leads ? ratio : 0,
                width: 1,
                height: 1 - ratio
            )
        } else {
            primaryRect = CGRect(
                x: leads ? 0 : 1 - ratio,
                y: 0,
                width: ratio,
                height: 1
            )
            secondaryRect = CGRect(
                x: leads ? ratio : 0,
                y: 0,
                width: 1 - ratio,
                height: 1
            )
        }

        return [
            item(
                primaryName,
                rect: primaryRect,
                color: .indigo,
                icon: "macwindow"
            ),
            item(
                secondaryName,
                rect: secondaryRect,
                color: .cyan,
                icon: "macwindow"
            )
        ]
    }

    private var customItems: [CommandLabPreviewItem] {
        guard let name = intent.arguments["scenario_name"],
              let scenario = scenarios.first(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            return []
        }
        let colors: [Color] = [
            .indigo,
            .cyan,
            .orange,
            .pink,
            .green,
            .purple
        ]
        return scenario.windows.enumerated().map { index, window in
            item(
                window.target.displayName,
                rect: CGRect(
                    x: window.gridRect.x,
                    y: window.gridRect.y,
                    width: window.gridRect.width,
                    height: window.gridRect.height
                ),
                color: colors[index % colors.count],
                icon: "macwindow"
            )
        }
    }

    private func pair(
        primary: String,
        secondary: String,
        ratio: CGFloat
    ) -> [CommandLabPreviewItem] {
        [
            item(
                primary,
                rect: CGRect(
                    x: 0,
                    y: 0,
                    width: ratio,
                    height: 1
                ),
                color: .indigo,
                icon: "macwindow"
            ),
            item(
                secondary,
                rect: CGRect(
                    x: ratio,
                    y: 0,
                    width: 1 - ratio,
                    height: 1
                ),
                color: .cyan,
                icon: "macwindow"
            )
        ]
    }

    private func item(
        _ name: String,
        rect: CGRect,
        color: Color,
        icon: String
    ) -> CommandLabPreviewItem {
        CommandLabPreviewItem(
            name: name,
            rect: rect,
            color: color,
            systemImage: icon
        )
    }
}

private struct CommandLabPreviewItem: Identifiable {
    let id = UUID()
    let name: String
    let rect: CGRect
    let color: Color
    let systemImage: String
}

private extension VoiceCommandAction {
    var commandLabTitle: String {
        switch self {
        case .applyCodeAndCall:
            return "Code + Call"
        case .applyDocumentationAndCode:
            return "Documentation + Code"
        case .applyNotesAndBrowser:
            return "Notes + Browser"
        case .arrangeDynamicWorkspace:
            return "Dynamic Workspace"
        case .showBrowserVideo:
            return "Browser Video"
        case .applyCustomScenario:
            return "Saved Cue"
        case .restorePreviousLayout:
            return "Restore Layout"
        }
    }

    var commandLabDetail: String {
        switch self {
        case .applyCodeAndCall:
            return "Editor fills the workspace; call video floats above it."
        case .applyDocumentationAndCode:
            return "Code gets 65%; reference material gets 35%."
        case .applyNotesAndBrowser:
            return "Browser gets 65%; notes get 35%."
        case .arrangeDynamicWorkspace:
            return "A custom two-window arrangement."
        case .showBrowserVideo:
            return "Extract only the active browser player."
        case .applyCustomScenario:
            return "Use the saved Cue named in the command."
        case .restorePreviousLayout:
            return "Return windows to their previous positions."
        }
    }

    var commandLabIcon: String {
        switch self {
        case .applyCodeAndCall:
            return "video.fill"
        case .applyDocumentationAndCode:
            return "book.pages"
        case .applyNotesAndBrowser:
            return "note.text"
        case .arrangeDynamicWorkspace:
            return "rectangle.3.group"
        case .showBrowserVideo:
            return "play.rectangle.fill"
        case .applyCustomScenario:
            return "square.grid.3x3"
        case .restorePreviousLayout:
            return "arrow.uturn.backward"
        }
    }
}
