/// What both looks say about keeping the FM-1 on while it installs.
///
/// Its screen stays dark while the loader writes, and switched off part-way, it may not start
/// again until the install is finished (FM1Kit's stage W3).
enum InstallWords {
    static let staysOn = "I'll leave it plugged in and switched on until it's done"
    static let staysOnDetail = """
        Its screen goes dark while it installs, which is normal. Keep the app open too. If anything \
        stops it, you can carry on where it left off.
        """
    static let takesAMinute = """
        Takes about a minute. Your FM-1's screen goes dark while it installs, and it restarts on its own.
        """
    static let darkScreen = "Its screen stays dark until it's done. Keep it plugged in and switched on."
    static let dontSwitchOff = """
        Don't switch it off. If switched off now, it may not start again. Its screen stays dark until \
        the install finishes.
        """
    static let plugBackIn = "Plug it back in, if it came out."
    static let reconnectThenResume = "DON'T SWITCH IT OFF. RECONNECT IT IF IT CAME OUT, THEN RESUME."
}
