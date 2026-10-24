/// The Mac has no alternate app icons, so Settings doesn't offer Retro's.
@MainActor
enum AlternateIcon {
    static let isAvailable = false

    static let isRetro = false

    static func set(retro _: Bool) async throws {}
}
