import AppKit
import PaneCueCore
import SwiftUI

private enum PaneCueOnboardingStep: Hashable {
    case mode
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition
    case ready
}

struct PaneCueOnboardingView: View {
    @ObservedObject var model: PaneCueDashboardModel
    @ObservedObject private var aiSettings: AIEngineSettingsStore
    @State private var step: PaneCueOnboardingStep = .mode

    init(model: PaneCueDashboardModel) {
        self.model = model
        _aiSettings = ObservedObject(wrappedValue: model.aiSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            Divider()

            ScrollView {
                VStack(spacing: 26) {
                    stepHeader
                    stepContent
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 48)
                .padding(.vertical, 42)
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            model.refreshPermissions()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshPermissions()
        }
    }

    private var steps: [PaneCueOnboardingStep] {
        var result: [PaneCueOnboardingStep] = [
            .mode,
            .accessibility,
            .screenRecording,
            .microphone
        ]
        if aiSettings.processingMode != .cloud {
            result.append(.speechRecognition)
        }
        result.append(.ready)
        return result
    }

    private var stepIndex: Int {
        steps.firstIndex(of: step) ?? 0
    }

    private var progressHeader: some View {
        HStack(spacing: 18) {
            Text("Initial Setup")
                .font(.headline)

            Spacer()

            Text("Step \(stepIndex + 1) of \(steps.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(steps.indices), id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= stepIndex
                                ? Color.accentColor
                                : Color.secondary.opacity(0.22)
                        )
                        .frame(
                            width: index == stepIndex ? 24 : 8,
                            height: 7
                        )
                        .animation(
                            .easeInOut(duration: 0.18),
                            value: stepIndex
                        )
                }
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 62)
    }

    @ViewBuilder
    private var stepHeader: some View {
        VStack(spacing: 14) {
            Image(systemName: stepIcon)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(stepColor)
                .frame(width: 62, height: 62)
                .background(
                    stepColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 18)
                )

            VStack(spacing: 7) {
                Text(stepTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(stepDetail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .mode:
            modeSelection
        case .accessibility,
             .screenRecording,
             .microphone,
             .speechRecognition:
            permissionCard
        case .ready:
            readySummary
        }
    }

    private var modeSelection: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(AIProcessingMode.allCases, id: \.self) { mode in
                OnboardingModeCard(
                    mode: mode,
                    isSelected: aiSettings.processingMode == mode
                ) {
                    aiSettings.processingMode = mode
                }
            }
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(
                    systemName: permissionGranted
                        ? "checkmark.circle.fill"
                        : "circle.dashed"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(permissionGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(permissionGranted ? "Access allowed" : "Waiting for access")
                        .font(.headline)
                    Text(permissionStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(permissionGranted ? "Ready" : "Not set")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(permissionGranted ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (permissionGranted ? Color.green : Color.orange)
                            .opacity(0.11),
                        in: Capsule()
                    )
            }
            .padding(18)
        }
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var readySummary: some View {
        VStack(spacing: 0) {
            OnboardingStatusRow(
                title: "Window Control",
                isReady: model.hasAccessibilityPermission
            )
            Divider()
            OnboardingStatusRow(
                title: "Browser and Call Video",
                isReady: model.hasScreenRecordingPermission
            )
            Divider()
            OnboardingStatusRow(
                title: "Voice Commands",
                isReady: model.hasMicrophonePermission
            )
            if aiSettings.processingMode != .cloud {
                Divider()
                OnboardingStatusRow(
                    title: "Offline Transcription",
                    isReady: model.hasSpeechRecognitionPermission
                )
            }
        }
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if stepIndex > 0 {
                Button("Back") {
                    moveBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if isPermissionStep, !permissionGranted {
                Button("Set Up Later") {
                    moveForward()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button(primaryButtonTitle) {
                performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .frame(height: 76)
    }

    private var isPermissionStep: Bool {
        switch step {
        case .accessibility,
             .screenRecording,
             .microphone,
             .speechRecognition:
            return true
        case .mode, .ready:
            return false
        }
    }

    private var permissionGranted: Bool {
        switch step {
        case .accessibility:
            return model.hasAccessibilityPermission
        case .screenRecording:
            return model.hasScreenRecordingPermission
        case .microphone:
            return model.hasMicrophonePermission
        case .speechRecognition:
            return model.hasSpeechRecognitionPermission
        case .mode, .ready:
            return false
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .mode:
            return "Continue"
        case .ready:
            return "Finish Setup"
        case .accessibility,
             .screenRecording,
             .microphone,
             .speechRecognition:
            return permissionGranted ? "Continue" : "Grant Access"
        }
    }

    private func performPrimaryAction() {
        switch step {
        case .mode:
            moveForward()
        case .accessibility:
            permissionGranted
                ? moveForward()
                : model.requestAccessibility()
        case .screenRecording:
            permissionGranted
                ? moveForward()
                : model.requestScreenRecordingAccess()
        case .microphone:
            permissionGranted
                ? moveForward()
                : model.requestMicrophoneAccess()
        case .speechRecognition:
            permissionGranted
                ? moveForward()
                : model.requestSpeechRecognitionAccess()
        case .ready:
            model.completeOnboarding()
        }
    }

    private func moveForward() {
        guard stepIndex + 1 < steps.count else {
            model.completeOnboarding()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = steps[stepIndex + 1]
        }
    }

    private func moveBack() {
        guard stepIndex > 0 else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = steps[stepIndex - 1]
        }
    }

    private var stepTitle: String {
        switch step {
        case .mode:
            return "Choose how commands are processed"
        case .accessibility:
            return "Allow window control"
        case .screenRecording:
            return "Enable floating video"
        case .microphone:
            return "Enable voice commands"
        case .speechRecognition:
            return "Enable offline transcription"
        case .ready:
            return "Setup is complete"
        }
    }

    private var stepDetail: String {
        switch step {
        case .mode:
            return "You can change this later. Cloud Only keeps local models out of memory."
        case .accessibility:
            return "PaneCue uses Accessibility only to move, resize, and restore application windows."
        case .screenRecording:
            return "This is used to isolate call video and browser players in a small floating window."
        case .microphone:
            return "Audio is captured only while a voice command is active."
        case .speechRecognition:
            return "macOS transcribes commands on this Mac when PaneCue works without the internet."
        case .ready:
            return "PaneCue will not repeat this setup automatically. You can reopen it from Settings."
        }
    }

    private var permissionStatusDetail: String {
        switch step {
        case .accessibility:
            return "Needed to arrange and restore windows"
        case .screenRecording:
            return "Needed only for floating call and browser video"
        case .microphone:
            return "Needed only when you start a voice command"
        case .speechRecognition:
            return "Not used in Cloud Only mode"
        case .mode, .ready:
            return ""
        }
    }

    private var stepIcon: String {
        switch step {
        case .mode:
            return "cpu"
        case .accessibility:
            return "macwindow"
        case .screenRecording:
            return "play.rectangle.on.rectangle"
        case .microphone:
            return "mic"
        case .speechRecognition:
            return "waveform.and.mic"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    private var stepColor: Color {
        switch step {
        case .mode:
            return .purple
        case .accessibility:
            return .blue
        case .screenRecording:
            return .pink
        case .microphone:
            return .orange
        case .speechRecognition:
            return .indigo
        case .ready:
            return .green
        }
    }
}

private struct OnboardingModeCard: View {
    let mode: AIProcessingMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)

                    Spacer()

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color.secondary
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.10)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(
                        isSelected
                            ? Color.accentColor
                            : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch mode {
        case .automatic:
            return "arrow.triangle.branch"
        case .offline:
            return "lock.laptopcomputer"
        case .cloud:
            return "cloud"
        }
    }

    private var tint: Color {
        switch mode {
        case .automatic:
            return .purple
        case .offline:
            return .blue
        case .cloud:
            return .cyan
        }
    }
}

private struct OnboardingStatusRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: isReady
                    ? "checkmark.circle.fill"
                    : "clock.badge.exclamationmark"
            )
            .foregroundStyle(isReady ? .green : .orange)
            .frame(width: 22)

            Text(title)
                .font(.body.weight(.medium))

            Spacer()

            Text(isReady ? "Ready" : "Set up later")
                .font(.caption.weight(.medium))
                .foregroundStyle(isReady ? .green : .secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}
