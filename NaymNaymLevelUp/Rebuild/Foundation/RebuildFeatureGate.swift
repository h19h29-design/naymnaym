import Foundation

enum RebuildFeatureGate {
    static func isEnabled(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if let index = arguments.firstIndex(of: "-native-rebuild-enabled"),
           arguments.indices.contains(index + 1) {
            return arguments[index + 1].uppercased() == "YES"
        }

        return defaults.bool(forKey: "native-rebuild-enabled")
    }
}
