import AppKit
@preconcurrency import AVFoundation
import Foundation
import PaneCueCore
@preconcurrency import Speech

enum PaneCueDiagnostics {
    static func report(
        scenarios: [CustomScenario],
        correctionCount: Int,
        features: PaneCueFeatureDiagnostics
    ) -> String {
        let bundle = Bundle.main
        let identity = PaneCueReleaseIdentity(
            infoDictionary: bundle.infoDictionary
        )
        let report = Report(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            application: ApplicationSummary(
                version: identity.version,
                build: identity.build,
                profile: features.profile,
                processing: features.processing
            ),
            system: SystemSummary(
                macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: architecture,
                displayCount: NSScreen.screens.count
            ),
            permissions: PermissionSummary(
                accessibility: AXIsProcessTrusted(),
                microphone: microphoneStatus,
                speechRecognition: speechRecognitionStatus,
                screenRecording: features.screenRecording
            ),
            localData: LocalDataSummary(
                cueCount: scenarios.count,
                correctionCount: correctionCount,
                cues: scenarios.map(CueSummary.init)
            ),
            privacy: [
                "No window titles are included.",
                "No application names or bundle identifiers are included.",
                "No URLs or document paths are included.",
                "This report is created locally and is exported only when you choose a file."
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let value = String(data: data, encoding: .utf8) else {
            return "{\n  \"error\" : \"Could not create diagnostics\"\n}"
        }
        return value
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static var microphoneStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not requested"
        @unknown default: return "unknown"
        }
    }

    private static var speechRecognitionStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not requested"
        @unknown default: return "unknown"
        }
    }

    private struct Report: Encodable {
        let schemaVersion: Int
        let generatedAt: String
        let application: ApplicationSummary
        let system: SystemSummary
        let permissions: PermissionSummary
        let localData: LocalDataSummary
        let privacy: [String]
    }

    private struct ApplicationSummary: Encodable {
        let version: String
        let build: String
        let profile: String
        let processing: String
    }

    private struct SystemSummary: Encodable {
        let macOS: String
        let architecture: String
        let displayCount: Int
    }

    private struct PermissionSummary: Encodable {
        let accessibility: Bool
        let microphone: String
        let speechRecognition: String
        let screenRecording: String
    }

    private struct LocalDataSummary: Encodable {
        let cueCount: Int
        let correctionCount: Int
        let cues: [CueSummary]
    }

    private struct CueSummary: Encodable {
        let windowCount: Int
        let roleTargetCount: Int
        let applicationTargetCount: Int
        let externalDisplayWindowCount: Int
        let launchEnabledCount: Int
        let configuredURLCount: Int

        init(_ cue: CustomScenario) {
            windowCount = cue.windows.count
            roleTargetCount = cue.windows.filter {
                $0.target.kind == .role
            }.count
            applicationTargetCount = cue.windows.filter {
                $0.target.kind == .application
            }.count
            externalDisplayWindowCount = cue.windows.filter {
                $0.display == .external
            }.count
            launchEnabledCount = cue.windows.filter(\.launchIfNeeded).count
            configuredURLCount = cue.windows.filter {
                !$0.urlString.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }.count
        }
    }
}
