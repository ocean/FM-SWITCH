/// What the app says about update notifications, the same in both looks.
enum UpdateNoticeWords {
    static let toggle = "Tell me when my saved firmwares update"
    @MainActor static var explained: String {
        """
        Only for firmwares saved on this \(ThisDevice.name), not starred ones. The list is checked about \
        once a day, so a notification can come a day or so after a release.
        """
    }
    static let refused = """
        Notifications are off for FM-SWITCH. Turn them on in your Notifications settings, then try \
        again.
        """
    static let offerDetail = "Get a notification when a firmware you've saved has a newer release."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
}
