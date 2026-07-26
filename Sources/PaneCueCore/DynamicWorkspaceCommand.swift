import Foundation

public enum DynamicWorkspaceArgument {
    public static let primaryKind = "primary_kind"
    public static let primaryValue = "primary_value"
    public static let primaryName = "primary_name"
    public static let secondaryKind = "secondary_kind"
    public static let secondaryValue = "secondary_value"
    public static let secondaryName = "secondary_name"
    public static let primaryRatio = "primary_ratio"
    public static let axis = "axis"
    public static let primaryPosition = "primary_position"
}

/// Extracts the concrete applications and relative layout from a natural
/// language command after the tiny model has identified a window-management
/// request. It intentionally handles slots deterministically so PaneCue never
/// invents an application or an unsafe action.
public enum DynamicWorkspaceCommandParser {
    private struct Target: Equatable {
        var kind: String
        var value: String
        var name: String
        var location: Int
        var endLocation: Int
    }

    private struct Alias {
        var phrases: [String]
        var kind: String
        var value: String
        var name: String
    }

    private static let aliases: [Alias] = [
        application(
            ["visual studio code", "vs code", "vscode", "вс код", "вскод"],
            bundleIdentifier: "com.microsoft.VSCode",
            name: "VS Code"
        ),
        application(
            ["xcode", "икскод", "экскод"],
            bundleIdentifier: "com.apple.dt.Xcode",
            name: "Xcode"
        ),
        application(
            ["cursor", "курсор"],
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            name: "Cursor"
        ),
        application(
            ["windsurf", "виндсерф"],
            bundleIdentifier: "com.exafunction.windsurf",
            name: "Windsurf"
        ),
        application(
            ["zed", "зед"],
            bundleIdentifier: "dev.zed.Zed",
            name: "Zed"
        ),
        application(
            ["pycharm", "пайчарм"],
            bundleIdentifier: "com.jetbrains.pycharm",
            name: "PyCharm"
        ),
        application(
            ["intellij idea", "intellij", "интеллиджей"],
            bundleIdentifier: "com.jetbrains.intellij",
            name: "IntelliJ IDEA"
        ),
        application(
            ["sublime text", "sublime", "саблайм"],
            bundleIdentifier: "com.sublimetext.4",
            name: "Sublime Text"
        ),
        application(
            ["terminal", "терминал"],
            bundleIdentifier: "com.apple.Terminal",
            name: "Terminal"
        ),
        application(
            ["iterm", "айтерм"],
            bundleIdentifier: "com.googlecode.iterm2",
            name: "iTerm"
        ),
        application(
            ["google chrome", "chrome", "хром"],
            bundleIdentifier: "com.google.Chrome",
            name: "Chrome"
        ),
        application(
            ["safari", "сафари"],
            bundleIdentifier: "com.apple.Safari",
            name: "Safari"
        ),
        application(
            ["firefox", "фаерфокс"],
            bundleIdentifier: "org.mozilla.firefox",
            name: "Firefox"
        ),
        application(
            ["arc browser", "arc", "арк"],
            bundleIdentifier: "company.thebrowser.Browser",
            name: "Arc"
        ),
        application(
            ["brave browser", "brave", "брейв"],
            bundleIdentifier: "com.brave.Browser",
            name: "Brave"
        ),
        application(
            ["microsoft edge", "edge", "эдж"],
            bundleIdentifier: "com.microsoft.edgemac",
            name: "Microsoft Edge"
        ),
        application(
            ["apple notes", "notes app"],
            bundleIdentifier: "com.apple.Notes",
            name: "Notes"
        ),
        application(
            ["notion", "ноушен"],
            bundleIdentifier: "notion.id",
            name: "Notion"
        ),
        application(
            ["obsidian", "обсидиан"],
            bundleIdentifier: "md.obsidian",
            name: "Obsidian"
        ),
        application(
            ["figma", "фигма"],
            bundleIdentifier: "com.figma.Desktop",
            name: "Figma"
        ),
        application(
            ["telegram", "телеграм"],
            bundleIdentifier: "ru.keepcoder.Telegram",
            name: "Telegram"
        ),
        application(
            ["slack", "слак"],
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            name: "Slack"
        ),
        application(
            ["discord", "дискорд"],
            bundleIdentifier: "com.hnc.Discord",
            name: "Discord"
        ),
        application(
            ["bear", "беар"],
            bundleIdentifier: "net.shinyfrog.bear",
            name: "Bear"
        ),
        application(
            ["craft", "крафт"],
            bundleIdentifier: "com.lukilabs.lukiapp",
            name: "Craft"
        ),
        application(
            ["preview", "просмотр"],
            bundleIdentifier: "com.apple.Preview",
            name: "Preview"
        ),
        application(
            ["finder", "файндер"],
            bundleIdentifier: "com.apple.finder",
            name: "Finder"
        ),
        application(
            ["calendar", "календарь"],
            bundleIdentifier: "com.apple.iCal",
            name: "Calendar"
        ),
        application(
            ["mail", "почта"],
            bundleIdentifier: "com.apple.mail",
            name: "Mail"
        ),
        role(
            ["редактор кода", "редактор", "ide"],
            role: .ide
        ),
        role(
            ["браузер", "browser", "web browser"],
            role: .browser
        ),
        role(
            [
                "заметки",
                "заметка",
                "заментки",
                "блокнот",
                "notes",
                "notebook"
            ],
            role: .notes
        ),
        role(
            ["документация", "documentation", "docs", "справка"],
            role: .documentation
        ),
        role(
            ["созвон", "звонок", "meeting", "call"],
            role: .meeting
        )
    ]

    /// Returns every concrete application or role mentioned in the command,
    /// in spoken order. Workspace Plan uses this to support more than the
    /// legacy two-window intent without asking a language model to invent
    /// targets.
    public static func mentionedTargets(
        in transcript: String
    ) -> [ScenarioWindowTarget] {
        matchedTargets(in: normalize(transcript)).compactMap { target in
            if target.kind == "role",
               let role = ApplicationRole(rawValue: target.value) {
                return ScenarioWindowTarget(role: role)
            }
            guard target.kind == "application" else {
                return nil
            }
            return ScenarioWindowTarget(
                application: ScenarioApplication(
                    bundleIdentifier: target.value,
                    displayName: target.name
                )
            )
        }
    }

    public static func intent(from transcript: String) -> VoiceCommandIntent? {
        let text = normalize(transcript)
        guard (
            hasActionVerb(text)
                || hasExplicitLayoutRequest(in: transcript)
        ), !isNegated(text) else {
            return nil
        }

        var targets = matchedTargets(in: text)
        guard targets.count >= 2 else {
            return nil
        }
        targets = Array(targets.prefix(2))

        let equal = containsAny(
            text,
            [
                "поровну",
                "одинакового размера",
                "одинаково",
                "пополам",
                "50 50",
                "50 на 50",
                "equal",
                "same size",
                "half and half"
            ]
        )
        let smallerLocation = markerLocation(
            in: text,
            markers: [
                "чуть поменьше",
                "поменьше",
                "намного меньше",
                "маленьк",
                "компактн",
                "вспомогательн",
                "узк",
                "уже",
                "a little smaller",
                "smaller",
                "small",
                "compact",
                "secondary",
                "narrow"
            ]
        )
        let largerLocation = markerLocation(
            in: text,
            markers: [
                "больш",
                "побольше",
                "намного больше",
                "главн",
                "основн",
                "на весь экран",
                "шире",
                "две трети",
                "70 на 30",
                "70 30",
                "larger",
                "large",
                "main",
                "primary",
                "full screen"
            ]
        )

        var primaryIndex = 0
        var ratio = 0.5
        if !equal {
            if let smallerLocation {
                let smaller = nearestTarget(
                    to: smallerLocation,
                    targets: targets
                )
                primaryIndex = smaller == 0 ? 1 : 0
                ratio = requestedRatio(in: text)
            } else if let largerLocation {
                primaryIndex = nearestTarget(
                    to: largerLocation,
                    targets: targets
                )
                ratio = requestedRatio(in: text)
            }
        }

        let secondaryIndex = primaryIndex == 0 ? 1 : 0
        let primary = targets[primaryIndex]
        let secondary = targets[secondaryIndex]
        let axis = containsAny(
            text,
            ["сверху", "снизу", "над ", "под ", "above", "below", "top", "bottom"]
        ) ? "vertical" : "horizontal"
        let primaryPosition = position(
            of: primary,
            relativeTo: secondary,
            in: text,
            axis: axis
        )

        return VoiceCommandIntent(
            action: .arrangeDynamicWorkspace,
            arguments: [
                DynamicWorkspaceArgument.primaryKind: primary.kind,
                DynamicWorkspaceArgument.primaryValue: primary.value,
                DynamicWorkspaceArgument.primaryName: primary.name,
                DynamicWorkspaceArgument.secondaryKind: secondary.kind,
                DynamicWorkspaceArgument.secondaryValue: secondary.value,
                DynamicWorkspaceArgument.secondaryName: secondary.name,
                DynamicWorkspaceArgument.primaryRatio: String(ratio),
                DynamicWorkspaceArgument.axis: axis,
                DynamicWorkspaceArgument.primaryPosition: primaryPosition
            ]
        )
    }

    public static func hasExplicitLayoutRequest(
        in transcript: String
    ) -> Bool {
        let text = normalize(transcript)
        return containsAny(
            text,
            [
                "поровну",
                "пополам",
                "50 на 50",
                "70 на 30",
                "две трети",
                "слева",
                "справа",
                "сверху",
                "снизу",
                "поменьше",
                "побольше",
                "больш",
                "маленьк",
                "компактн",
                "узк",
                "уже",
                "шире",
                "на весь экран",
                "equal",
                "half and half",
                "seventy thirty",
                "two thirds",
                "left",
                "right",
                "above",
                "below",
                "smaller",
                "larger",
                "small",
                "compact",
                "narrow",
                "wider",
                "full screen"
            ]
        )
    }

    private static func matchedTargets(in text: String) -> [Target] {
        var matches: [Target] = []
        var occupied: [Range<String.Index>] = []
        let sortedAliases = aliases.flatMap { alias in
            alias.phrases.map { phrase in
                (phrase: normalize(phrase), alias: alias)
            }
        }.sorted { $0.phrase.count > $1.phrase.count }

        for candidate in sortedAliases {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: candidate.phrase,
                    range: searchStart..<text.endIndex
                  ) {
                searchStart = range.upperBound
                guard !occupied.contains(where: { $0.overlaps(range) }) else {
                    continue
                }
                let location = text.distance(
                    from: text.startIndex,
                    to: range.lowerBound
                )
                matches.append(
                    Target(
                        kind: candidate.alias.kind,
                        value: candidate.alias.value,
                        name: candidate.alias.name,
                        location: location,
                        endLocation: text.distance(
                            from: text.startIndex,
                            to: range.upperBound
                        )
                    )
                )
                occupied.append(range)
                break
            }
        }

        return matches
            .sorted { $0.location < $1.location }
            .reduce(into: []) { result, target in
                guard !result.contains(where: {
                    $0.kind == target.kind && $0.value == target.value
                }) else {
                    return
                }
                result.append(target)
            }
    }

    private static func nearestTarget(
        to location: Int,
        targets: [Target]
    ) -> Int {
        targets.indices.min {
            distance(from: location, to: targets[$0])
                < distance(from: location, to: targets[$1])
        } ?? 0
    }

    private static func distance(
        from location: Int,
        to target: Target
    ) -> Int {
        if location < target.location {
            return target.location - location
        }
        if location > target.endLocation {
            return location - target.endLocation
        }
        return 0
    }

    private static func position(
        of target: Target,
        relativeTo secondary: Target,
        in text: String,
        axis: String
    ) -> String {
        let markers: [(String, String)]
        if axis == "vertical" {
            markers = [
                ("сверху", "leading"),
                ("над ", "leading"),
                ("above", "leading"),
                ("top", "leading"),
                ("снизу", "trailing"),
                ("под ", "trailing"),
                ("below", "trailing"),
                ("bottom", "trailing")
            ]
        } else {
            markers = [
                ("слева", "leading"),
                ("left", "leading"),
                ("справа", "trailing"),
                ("right", "trailing")
            ]
        }

        let located = markers.compactMap { marker, position in
            text.range(of: marker).map { range in
                let markerLocation = text.distance(
                    from: text.startIndex,
                    to: range.lowerBound
                )
                let primaryDistance = distance(
                    from: markerLocation,
                    to: target
                )
                let secondaryDistance = distance(
                    from: markerLocation,
                    to: secondary
                )
                return (
                    distance: min(
                        primaryDistance,
                        secondaryDistance
                    ),
                    position: primaryDistance <= secondaryDistance
                        ? position
                        : opposite(position)
                )
            }
        }
        return located.min { $0.distance < $1.distance }?.position
            ?? "leading"
    }

    private static func opposite(_ position: String) -> String {
        position == "leading" ? "trailing" : "leading"
    }

    private static func markerLocation(
        in text: String,
        markers: [String]
    ) -> Int? {
        markers.compactMap { marker in
            text.range(of: marker).map {
                text.distance(from: text.startIndex, to: $0.lowerBound)
            }
        }.min()
    }

    private static func hasActionVerb(_ text: String) -> Bool {
        containsAny(
            text,
            [
                "открой",
                "постав",
                "располож",
                "размест",
                "покажи",
                "сделай",
                "вывед",
                "остав",
                "хочу",
                "open",
                "put",
                "arrange",
                "place",
                "show",
                "make",
                "keep"
            ]
        )
    }

    private static func isNegated(_ text: String) -> Bool {
        containsAny(
            text,
            [
                "не откры",
                "не став",
                "не располаг",
                "не размещ",
                "не меняй",
                "ничего не делай",
                "do not",
                "don t",
                "nothing"
            ]
        )
    }

    private static func strongSizeMarker(_ text: String) -> Bool {
        containsAny(
            text,
            [
                "намного",
                "больш",
                "маленьк",
                "компактн",
                "на весь экран",
                "узк",
                "две трети",
                "70 на 30",
                "70 30",
                "much ",
                "tiny",
                "compact",
                "full screen"
            ]
        )
    }

    private static func requestedRatio(in text: String) -> Double {
        if containsAny(
            text,
            [
                "почти на весь экран",
                "почти весь экран",
                "almost full screen"
            ]
        ) {
            return 0.8
        }
        if containsAny(
            text,
            [
                "70 на 30",
                "70 30",
                "seventy thirty"
            ]
        ) {
            return 0.7
        }
        if containsAny(
            text,
            [
                "две трети",
                "2 thirds",
                "two thirds"
            ]
        ) {
            return 0.67
        }
        return strongSizeMarker(text) ? 0.75 : 0.65
    }

    private static func containsAny(
        _ text: String,
        _ phrases: [String]
    ) -> Bool {
        phrases.contains { text.contains(normalize($0)) }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-zа-яё0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func application(
        _ phrases: [String],
        bundleIdentifier: String,
        name: String
    ) -> Alias {
        Alias(
            phrases: phrases,
            kind: "application",
            value: bundleIdentifier,
            name: name
        )
    }

    private static func role(
        _ phrases: [String],
        role: ApplicationRole
    ) -> Alias {
        Alias(
            phrases: phrases,
            kind: "role",
            value: role.rawValue,
            name: role.displayName
        )
    }
}
