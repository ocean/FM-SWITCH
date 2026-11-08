import FM1Kit

/// The words about switching away from a firmware, which both looks show.
enum SwitchingWords {
    static let warningTitle = "Switching away later"
    static let decline = "Don't install"
    static let notReallyOfficial = "It's really running another firmware"

    /// What to know before installing the firmware `guide` is for, in place of FM1Kit's own
    /// warnings, which say going back takes two installs, where FM-SWITCH does both.
    static func warnings(_ guide: LeavingGuide) -> [String] {
        let name = guide.firmwareName
        var warnings: [String] = []
        let refused = [(LeavingDestination.v15, "V15"), (.v16, "V16")]
            .filter { guide.route(to: $0.0) == .throughFixedFirmware }
            .map(\.1)
        if !refused.isEmpty {
            warnings.append(
                """
                Once \(name) is installed, it can't install \(refused.joined(separator: " or ")) \
                straight away. FM-SWITCH puts MIDIMON on first when you go back, so it takes a little \
                longer. On a Mac, download mode can do it in one.
                """)
        }
        if SwitchingGuide.reportsOfficialIdentity(guide) {
            warnings.append(
                """
                \(name) reports itself as V15, so apps can't tell them apart. When you switch away, FM-SWITCH \
                may ask whether it's really running another firmware.
                """)
        }
        return warnings
    }

    /// Why MIDIMON or LOOM-8 goes on first.
    static func firstStep(_ firstStep: String, running: String, next: String) -> String {
        """
        \(firstStep) goes on first: \(running) can't install \(next) directly, but it can install \
        \(firstStep), which can.
        """
    }

    /// Why the install can't start: MIDIMON has to go on first, and couldn't be had.
    static func missingFirstStep(running: String, next: String, problem: String?) -> String {
        ["\(running) can't install \(next) directly, so MIDIMON has to go on first.", problem]
            .compactMap(\.self)
            .joined(separator: " ")
    }

    /// The FM-1 reports the official firmware being installed, which it may not be running.
    static func alreadyOfficial(_ identity: FM1Identity) -> String {
        let name = officialName(identity)
        return """
            Your FM-1 says it's running \(name), so there's nothing to install, unless it's really \
            running a firmware that reports itself as \(name).
            """
    }

    static func notReallyOfficialDetail(_ identity: FM1Identity) -> String {
        let name = officialName(identity)
        return "Such as TransitFM1, which reports itself as \(name). Tick this to install \(name) over it."
    }

    /// The saved guide says the FM-1 is running a firmware that reports the official one's identity.
    static func replacesLookAlike(_ running: String, reporting identity: FM1Identity) -> String {
        let name = officialName(identity)
        return "Your FM-1 is running \(running), which reports itself as \(name). This installs \(name) over it."
    }

    /// What's left after V15 goes on over V16 without a Mac, which putting back its sounds won't fix.
    #if os(macOS)
        static let stillMono = """
            After V16, V15 plays one note at a time until its saved data is cleared, which putting \
            back the factory sounds won't do. To clear it, install V15 again in Backup & rescue, with \
            Start the new firmware fresh ticked.
            """
    #else
        static let stillMono = """
            After V16, V15 plays one note at a time until its saved data is cleared, which putting \
            back the factory sounds won't do. To clear it, install V15 again from a Mac, in \
            FM-SWITCH's Backup & rescue, with Start the new firmware fresh ticked.
            """
    #endif

    /// What the install that stopped will do instead, putting MIDIMON or LOOM-8 on first.
    static func installFirst(_ firstStep: String) -> String {
        "Install \(firstStep) first"
    }

    static func installFirstDetail(_ firstStep: String, then next: String) -> String {
        "\(firstStep) goes on, then \(next) from it. Your FM-1 restarts on its own in between."
    }

    /// V15 or V16, for an FM-1 reporting the official firmware's identity.
    private static func officialName(_ identity: FM1Identity) -> String {
        identity == .officialV16 ? "V16" : "V15"
    }
}
