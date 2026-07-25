import AppKit

@MainActor
enum PaneCueBrandAssets {
    enum TintColor: String, CaseIterable {
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case graphite = "Graphite"

        init(systemValue: String?, accentColor: Int?) {
            switch systemValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            {
            case "red", "красный":
                self = .red
            case "orange", "оранжевый":
                self = .orange
            case "yellow", "желтый", "жёлтый":
                self = .yellow
            case "green", "зеленый", "зелёный":
                self = .green
            case "blue", "синий":
                self = .blue
            case "purple", "lilac", "лиловый", "фиолетовый":
                self = .purple
            case "pink", "розовый":
                self = .pink
            case "graphite", "gray", "grey", "графит":
                self = .graphite
            default:
                self = Self.from(accentColor: accentColor)
            }
        }

        private static func from(accentColor: Int?) -> Self {
            switch accentColor {
            case -1:
                .graphite
            case 0:
                .red
            case 1:
                .orange
            case 2:
                .yellow
            case 3:
                .green
            case 5:
                .purple
            case 6:
                .pink
            default:
                .blue
            }
        }
    }

    enum Appearance: String {
        case standard
        case dark
        case clearLight
        case clearDark
        case tintedLight
        case tintedDark

        init(theme: String?) {
            switch theme {
            case let value? where value.hasPrefix("Clear"):
                self = value.hasSuffix("Light") ? .clearLight : .clearDark
            case let value? where value.hasPrefix("Tinted"):
                self = value.hasSuffix("Light") ? .tintedLight : .tintedDark
            case let value? where value.hasPrefix("Regular"):
                self = value.hasSuffix("Light") ? .standard : .dark
            default:
                self = .standard
            }
        }

        func resourceName(tintColor: TintColor) -> String {
            switch self {
            case .standard:
                "AppIcon-Default"
            case .dark:
                "AppIcon-Dark"
            case .clearLight:
                "AppIcon-Clear-Light"
            case .clearDark:
                "AppIcon-Clear-Dark"
            case .tintedLight:
                "AppIcon-Tinted-\(tintColor.rawValue)-Light"
            case .tintedDark:
                "AppIcon-Tinted-\(tintColor.rawValue)-Dark"
            }
        }
    }

    private static var cachedIcons: [String: NSImage] = [:]

    static var currentAppearance: Appearance {
        Appearance(
            theme: UserDefaults.standard.string(
                forKey: "AppleIconAppearanceTheme"
            )
        )
    }

    static var currentTintColor: TintColor {
        TintColor(
            systemValue: UserDefaults.standard.string(
                forKey: "AppleIconAppearanceTintColor"
            ),
            accentColor: UserDefaults.standard.object(
                forKey: "AppleAccentColor"
            ) as? Int
        )
    }

    static var appIcon: NSImage {
        icon(
            for: currentAppearance,
            tintColor: currentTintColor
        )
    }

    static func icon(
        for appearance: Appearance,
        tintColor: TintColor
    ) -> NSImage {
        let resourceName = appearance.resourceName(tintColor: tintColor)
        if let cached = cachedIcons[resourceName] {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return NSApp.applicationIconImage
        }
        image.accessibilityDescription = "PaneCue"
        cachedIcons[resourceName] = image
        return image
    }

    static let statusIcon: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "PaneCueStatusTemplate",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "PaneCue"
        return image
    }()
}

extension Notification.Name {
    static let paneCueAppIconDidChange = Notification.Name(
        "PaneCueAppIconDidChange"
    )
}

@MainActor
final class PaneCueAppIconController {
    private var currentSignature: String?
    private var timer: Timer?

    func start() {
        updateIfNeeded()
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateIfNeeded()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateIfNeeded() {
        let appearance = PaneCueBrandAssets.currentAppearance
        let tintColor = PaneCueBrandAssets.currentTintColor
        let signature = "\(appearance.rawValue):\(tintColor.rawValue)"
        guard signature != currentSignature else {
            return
        }
        currentSignature = signature
        NSApp.applicationIconImage = PaneCueBrandAssets.icon(
            for: appearance,
            tintColor: tintColor
        )
        NotificationCenter.default.post(
            name: .paneCueAppIconDidChange,
            object: signature
        )
    }
}
