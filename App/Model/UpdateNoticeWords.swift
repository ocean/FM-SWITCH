/// What the app says about update notifications, the same in both looks.
enum UpdateNoticeWords {
    static let toggle = "Tell me when my saved firmwares update"
    static let explained = """
        A notification when a firmware you've saved has a newer release. The list is checked about \
        once a day.
        """
    static let refused = """
        Notifications are off for FM-SWITCH. Turn them on in your Notifications settings, then try \
        again.
        """
    static let offerDetail = "Get a notification when a firmware you've saved has a newer release."
    static let turnOn = "Turn on"
    static let notNow = "Not now"
}
