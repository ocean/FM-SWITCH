/// AppKit's look, where SwiftUI can't set it: nothing to change on the Mac.
enum SystemAppearance {
    @MainActor static func apply(for _: Look) {}
}
