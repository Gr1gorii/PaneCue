import Foundation

public struct ScenarioApplication: Codable, Hashable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

public enum ScenarioTargetKind: String, Codable, Hashable, Sendable {
    case application
    case role
}

public struct ScenarioWindowTarget: Codable, Hashable, Sendable {
    public var kind: ScenarioTargetKind
    public var application: ScenarioApplication?
    public var role: ApplicationRole?

    public init(application: ScenarioApplication) {
        kind = .application
        self.application = application
        role = nil
    }

    public init(role: ApplicationRole) {
        kind = .role
        application = nil
        self.role = role
    }

    public var displayName: String {
        switch kind {
        case .application:
            return application?.displayName ?? "Choose an application"
        case .role:
            return (role ?? .other).displayName
        }
    }

    public var normalized: ScenarioWindowTarget {
        switch kind {
        case .application:
            if let application,
               !application.bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ScenarioWindowTarget(application: application)
            }
            return ScenarioWindowTarget(role: .other)
        case .role:
            return ScenarioWindowTarget(role: role ?? .other)
        }
    }
}

public struct ScenarioGridRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        normalize()
    }

    public mutating func normalize(
        minimumWidth: Double = ScenarioGridResolution.minimumWidth,
        minimumHeight: Double = ScenarioGridResolution.minimumHeight
    ) {
        width = min(max(width, minimumWidth), 1)
        height = min(max(height, minimumHeight), 1)
        x = min(max(x, 0), 1 - width)
        y = min(max(y, 0), 1 - height)
    }

    public var normalized: ScenarioGridRect {
        var copy = self
        copy.normalize()
        return copy
    }

    public static let left = ScenarioGridRect(
        x: 0,
        y: 0,
        width: 0.65,
        height: 1
    )

    public static let right = ScenarioGridRect(
        x: 0.65,
        y: 0,
        width: 0.35,
        height: 1
    )
}

public enum ScenarioDisplayTarget: String, Codable, Hashable, Sendable,
    CaseIterable {
    case main
    case external

    public var displayName: String {
        switch self {
        case .main:
            return "Main display"
        case .external:
            return "External display"
        }
    }
}

public struct ScenarioWindowSlot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var target: ScenarioWindowTarget
    public var gridRect: ScenarioGridRect
    public var display: ScenarioDisplayTarget
    public var launchIfNeeded: Bool
    public var urlString: String

    public init(
        id: UUID = UUID(),
        target: ScenarioWindowTarget,
        gridRect: ScenarioGridRect,
        display: ScenarioDisplayTarget = .main,
        launchIfNeeded: Bool = true,
        urlString: String = ""
    ) {
        self.id = id
        self.target = target
        self.gridRect = gridRect.normalized
        self.display = display
        self.launchIfNeeded = launchIfNeeded
        self.urlString = urlString
    }
}

public struct ScenarioConditions: Codable, Hashable, Sendable {
    public var onlyDuringCall: Bool
    public var requiresExternalDisplay: Bool

    public init(
        onlyDuringCall: Bool = false,
        requiresExternalDisplay: Bool = false
    ) {
        self.onlyDuringCall = onlyDuringCall
        self.requiresExternalDisplay = requiresExternalDisplay
    }
}

public struct ScenarioHotKey: Codable, Hashable, Sendable {
    public var key: String
    public var usesCommand: Bool
    public var usesOption: Bool
    public var usesControl: Bool
    public var usesShift: Bool

    public init(
        key: String = "",
        usesCommand: Bool = false,
        usesOption: Bool = true,
        usesControl: Bool = true,
        usesShift: Bool = false
    ) {
        self.key = String(
            key.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .prefix(1)
        )
        self.usesCommand = usesCommand
        self.usesOption = usesOption
        self.usesControl = usesControl
        self.usesShift = usesShift
    }

    public var isEnabled: Bool {
        !key.isEmpty && (usesCommand || usesOption || usesControl || usesShift)
    }

    public var displayName: String {
        guard isEnabled else {
            return "Not set"
        }

        var value = ""
        if usesControl { value += "⌃" }
        if usesOption { value += "⌥" }
        if usesShift { value += "⇧" }
        if usesCommand { value += "⌘" }
        return value + key
    }
}

public struct CustomScenario: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var windows: [ScenarioWindowSlot]
    public var conditions: ScenarioConditions
    public var voicePhrase: String
    public var hotKey: ScenarioHotKey

    public init(
        id: UUID = UUID(),
        name: String,
        windows: [ScenarioWindowSlot],
        conditions: ScenarioConditions = ScenarioConditions(),
        voicePhrase: String = "",
        hotKey: ScenarioHotKey = ScenarioHotKey()
    ) {
        self.id = id
        self.name = name
        self.windows = windows.map {
            var slot = $0
            slot.target = slot.target.normalized
            slot.gridRect.normalize()
            return slot
        }
        self.conditions = conditions
        self.voicePhrase = voicePhrase
        self.hotKey = hotKey
    }

    public init(
        id: UUID = UUID(),
        name: String,
        primaryApplication: ScenarioApplication,
        secondaryApplication: ScenarioApplication,
        primaryRatio: Double = 0.65
    ) {
        self.id = id
        self.name = name
        let ratio = min(max(primaryRatio, 0.5), 0.8)
        windows = [
            ScenarioWindowSlot(
                target: ScenarioWindowTarget(
                    application: primaryApplication
                ),
                gridRect: ScenarioGridRect(
                    x: 0,
                    y: 0,
                    width: ratio,
                    height: 1
                )
            ),
            ScenarioWindowSlot(
                target: ScenarioWindowTarget(
                    application: secondaryApplication
                ),
                gridRect: ScenarioGridRect(
                    x: ratio,
                    y: 0,
                    width: 1 - ratio,
                    height: 1
                )
            )
        ]
        conditions = ScenarioConditions()
        voicePhrase = ""
        hotKey = ScenarioHotKey()
    }

    public var primaryApplication: ScenarioApplication {
        get {
            windows.first?.target.application
                ?? ScenarioApplication(
                    bundleIdentifier: "",
                    displayName: windows.first?.target.displayName
                        ?? "Primary window"
                )
        }
        set {
            guard !windows.isEmpty else {
                return
            }
            windows[0].target = ScenarioWindowTarget(application: newValue)
        }
    }

    public var secondaryApplication: ScenarioApplication {
        get {
            windows.dropFirst().first?.target.application
                ?? ScenarioApplication(
                    bundleIdentifier: "",
                    displayName: windows.dropFirst().first?.target.displayName
                        ?? "Secondary window"
                )
        }
        set {
            guard windows.count > 1 else {
                return
            }
            windows[1].target = ScenarioWindowTarget(application: newValue)
        }
    }

    public var primaryRatio: Double {
        get {
            min(max(windows.first?.gridRect.width ?? 0.65, 0.5), 0.8)
        }
        set {
            guard windows.count > 1 else {
                return
            }
            let ratio = min(max(newValue, 0.5), 0.8)
            windows[0].gridRect = ScenarioGridRect(
                x: 0,
                y: 0,
                width: ratio,
                height: 1
            )
            windows[1].gridRect = ScenarioGridRect(
                x: ratio,
                y: 0,
                width: 1 - ratio,
                height: 1
            )
        }
    }
}

extension CustomScenario: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case windows
        case conditions
        case voicePhrase
        case hotKey
        case primaryApplication
        case secondaryApplication
        case primaryRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id)
            ?? UUID()
        let name = try container.decode(String.self, forKey: .name)

        if let windows = try container.decodeIfPresent(
            [ScenarioWindowSlot].self,
            forKey: .windows
        ), !windows.isEmpty {
            self.init(
                id: id,
                name: name,
                windows: windows,
                conditions: try container.decodeIfPresent(
                    ScenarioConditions.self,
                    forKey: .conditions
                ) ?? ScenarioConditions(),
                voicePhrase: try container.decodeIfPresent(
                    String.self,
                    forKey: .voicePhrase
                ) ?? "",
                hotKey: try container.decodeIfPresent(
                    ScenarioHotKey.self,
                    forKey: .hotKey
                ) ?? ScenarioHotKey()
            )
            return
        }

        let primary = try container.decode(
            ScenarioApplication.self,
            forKey: .primaryApplication
        )
        let secondary = try container.decode(
            ScenarioApplication.self,
            forKey: .secondaryApplication
        )
        let ratio = try container.decodeIfPresent(
            Double.self,
            forKey: .primaryRatio
        ) ?? 0.65
        self.init(
            id: id,
            name: name,
            primaryApplication: primary,
            secondaryApplication: secondary,
            primaryRatio: ratio
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(windows, forKey: .windows)
        try container.encode(conditions, forKey: .conditions)
        try container.encode(voicePhrase, forKey: .voicePhrase)
        try container.encode(hotKey, forKey: .hotKey)
    }
}
