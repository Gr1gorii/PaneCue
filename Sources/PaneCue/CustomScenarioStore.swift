import Foundation
import PaneCueCore

@MainActor
final class CustomScenarioStore {
    private let defaults: UserDefaults

    private(set) var scenarios: [CustomScenario] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func replaceAll(with scenarios: [CustomScenario]) {
        self.scenarios = Self.normalized(scenarios)
        persist()
    }

    func scenario(id: UUID) -> CustomScenario? {
        scenarios.first { $0.id == id }
    }

    func scenario(named name: String) -> CustomScenario? {
        let normalizedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return scenarios.first {
            $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
                || (
                    !$0.voicePhrase.isEmpty
                        && $0.voicePhrase.caseInsensitiveCompare(
                            normalizedName
                        ) == .orderedSame
                )
        }
    }

    private func load() {
        let data = defaults.data(
            forKey: PaneCuePersistenceKey.customScenarios
        ) ?? defaults.data(
            forKey: PaneCuePersistenceKey.legacyCustomScenarios
        )
        guard let data,
              let decoded = try? JSONDecoder().decode(
                  [CustomScenario].self,
                  from: data
              )
        else {
            scenarios = []
            return
        }

        scenarios = Self.normalized(decoded)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scenarios) else {
            return
        }
        defaults.set(
            data,
            forKey: PaneCuePersistenceKey.customScenarios
        )
    }

    private static func normalized(
        _ scenarios: [CustomScenario]
    ) -> [CustomScenario] {
        var usedNames: Set<String> = []
        var usedHotKeys: Set<String> = []

        return scenarios.compactMap { scenario in
            var normalized = scenario
            normalized.name = normalized.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            normalized.voicePhrase = normalized.voicePhrase
                .trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.hotKey = ScenarioHotKey(
                key: normalized.hotKey.key,
                usesCommand: normalized.hotKey.usesCommand,
                usesOption: normalized.hotKey.usesOption,
                usesControl: normalized.hotKey.usesControl,
                usesShift: normalized.hotKey.usesShift
            )

            var usedWindowIDs: Set<UUID> = []
            normalized.windows = normalized.windows.prefix(8).map { window in
                var window = window
                window.target = window.target.normalized
                window.gridRect.normalize()
                window.urlString = window.urlString.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !usedWindowIDs.insert(window.id).inserted {
                    window.id = UUID()
                    usedWindowIDs.insert(window.id)
                }
                return window
            }

            guard !normalized.name.isEmpty,
                  normalized.windows.count >= 2
            else {
                return nil
            }

            let key = normalized.name.lowercased()
            guard usedNames.insert(key).inserted else {
                return nil
            }

            if normalized.hotKey.isEnabled {
                let hotKey = normalized.hotKey.displayName
                if !usedHotKeys.insert(hotKey).inserted {
                    normalized.hotKey = ScenarioHotKey()
                }
            }

            return normalized
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }
}
