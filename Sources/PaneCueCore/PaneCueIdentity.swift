public enum PaneCueIdentity {
    public static let bundleIdentifier = "io.github.gr1gorii.PaneCue"

    public static func subsystem(_ component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }
}
