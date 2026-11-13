import Foundation

/// The app's version and build, as people see them in About and in feedback.
enum AppVersion {
    /// Such as "0.2.1 (7)".
    static var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
