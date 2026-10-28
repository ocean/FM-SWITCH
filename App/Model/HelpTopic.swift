import Foundation

/// Something that can go wrong with an FM-1, and what to do about it: the Help page, in both
/// looks.
enum HelpTopic: String, CaseIterable, Identifiable {
    /// A firmware built on Felucca's earlier update code refuses V15, Open and most others, once
    /// the FM-1's bootloader has been changed.
    case wontInstall
    case stoppedHalfway
    case wontStart
    /// Not even in a firmware's USB recovery mode: only the chip's download mode is left.
    case wontStartAtAll
    case notSeen

    var id: String { rawValue }

    static let intro = "Something not right? Pick what you're seeing."

    var title: String {
        switch self {
        case .wontInstall: "It won't let me install another firmware"
        case .stoppedHalfway: "An install stopped halfway"
        case .wontStart: "It won't start"
        case .wontStartAtAll: "It won't start at all, even in recovery mode"
        case .notSeen: "FM-SWITCH can't see the FM-1"
        }
    }

    @MainActor
    var paragraphs: [String] {
        switch self {
        case .wontInstall:
            [
                """
                If your FM-1's bootloader has been changed, usually to m-bootloader, or by installing \
                M-VAVE's Open V12 or V14, some firmwares built on Felucca's update code (AMB-1, DUB-1, \
                HYP-1 and others) won't let you install V15, Open, or most firmwares not built on \
                Felucca. The FM-1 may show "UPDATE / CHECK HEAD / FAILED", or nothing at all.
                """,
                """
                Your FM-1 is fine: nothing was written, and it's still running the firmware it had. \
                Nobody did anything wrong. The update code has a careful safety check that assumes \
                M-VAVE's original bootloader is the only one.
                """,
                """
                There's a way round it, and it works from this \(ThisDevice.name) too. First install \
                MIDIMON 0.4 or LOOM-8 0.8. They're built on Felucca, so your firmware lets them in, but \
                their check is updated, so either can then install V15, Open or the firmware you wanted.
                """,
                """
                If you installed Open V12 or V14 before, some of these firmwares (DUB-1, for one) can \
                still install that same Open again. Open can then install V15.
                """,
                Self.wayBack,
            ]
        case .stoppedHalfway:
            [
                """
                The FM-1 stays in its update mode, waiting. Plug it back in and FM-SWITCH offers to \
                finish installing it.
                """
            ]
        case .wontStart:
            [
                """
                Some firmwares start USB recovery mode if you hold OCT− while switching the FM-1 on. \
                Then connect it and install a firmware you've saved. Not every firmware does this.
                """
            ]
        case .wontStartAtAll:
            [
                """
                A computer can usually still reach it through the chip's own download mode. An FM-1 \
                with damaged firmware often starts in that mode by itself, and shows up as a USB disk \
                called "WL82 UBOOT1.00".
                """,
                Self.downloadModeTools,
                "The firmware hub lists more rescue tools, for an FM-1 that doesn't get that far.",
            ]
        case .notSeen:
            [
                """
                Check it's switched on, and that the cable carries data: some only charge. Then unplug \
                it and plug it in again.
                """
            ] + Self.adapters
        }
    }

    var links: [CatalogueLink] {
        switch self {
        case .wontInstall:
            #if os(macOS)
                [Self.fmStatic]
            #else
                [Self.macApp, Self.mFlasher, Self.fmStatic]
            #endif
        case .wontStartAtAll:
            [Self.mFlasher, Self.fmStatic, Self.hubHelp]
        case .stoppedHalfway, .wontStart, .notSeen:
            []
        }
    }

    /// Whether it offers to open Backup & rescue, which only the Mac app has.
    var opensBackupAndRescue: Bool {
        #if os(macOS)
            self == .wontInstall || self == .wontStartAtAll
        #else
            false
        #endif
    }

    #if os(macOS)
        private static let wayBack = """
            If that doesn't work, open Backup & rescue. It writes the firmware in the chip's download mode, which \
            works whatever is installed and keeps your bootloader.
            """
        private static let downloadModeTools = """
            Backup & rescue can back it up, put a backup back or write a firmware, and install \
            m-bootloader, so holding REC always gets you back there.
            """
        private static let adapters: [String] = []
    #else
        private static let wayBack = """
            If that doesn't work, you'll need a computer. FM-SWITCH on a Mac writes the firmware in the chip's \
            download mode, which works whatever is installed and keeps your bootloader. M-Flasher, \
            for Mac, Windows and Linux, uses download mode too.
            """
        private static let downloadModeTools =
            "FM-SWITCH on a Mac, or M-Flasher, can back it up and reinstall it from there."
        /// Testers found a Lightning to USB-C cable doesn't work, but Apple's camera adapters do.
        private static let adapters = [
            """
            If your iPhone or iPad has a Lightning port, plug the FM-1 in through Apple's Lightning to \
            USB Camera Adapter or Lightning to USB 3 Camera Adapter. A Lightning to USB-C cable won't \
            work. Other Lightning adapters haven't been tested yet.
            """
        ]
    #endif

    private static let macApp = CatalogueLink(
        label: "FM-SWITCH for Mac", url: URL(literal: "https://github.com/ocean/FM-SWITCH/releases/latest"))
    private static let mFlasher = CatalogueLink(
        label: "M-Flasher", url: URL(literal: "https://github.com/jvitkauskas/m-flasher"))
    private static let fmStatic = CatalogueLink(
        label: "fm-static", url: URL(literal: "https://seajaysec.github.io/fm-static/"))
    private static let hubHelp = CatalogueLink(
        label: "The firmware hub's help", url: URL(literal: "https://thefirmwarehub.com/kb/#back"))
}
