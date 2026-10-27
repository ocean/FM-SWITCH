import SwiftUI

/// The risk and recovery notice: shown full screen on first run, and kept in SETUP.
enum SafetyNotice {
    /// Bump when the wording changes materially, so everyone sees it again once.
    static let version = 2

    static let text = """
        Not affiliated with M-Vave. Though this utility makes every attempt to correctly reset and \
        safely flash your device, flashing custom firmware is at your own risk.
        """

    #if os(macOS)
        static let recovery = """
            If your FM-1 won't start, some firmwares can start it in USB recovery mode if you hold \
            down the "OCT−" key while switching it on. Then connect it and install a firmware you've \
            saved. Not every firmware does this, and if yours doesn't, Backup & rescue can usually \
            still reach it: the app's settings say more.
            """
    #else
        static let recovery = """
            If your FM-1 won't start, some firmwares can start it in USB recovery mode if you hold \
            down the "OCT−" key while switching it on. Then connect it and install a firmware you've \
            saved. Not every firmware does this, and if yours doesn't, recovery needs a computer: the \
            app's settings say more.
            """
    #endif

    /// What's left when the FM-1 won't start at all.
    ///
    /// The other tools are other people's, and haven't been tried with FM-SWITCH.
    #if os(macOS)
        static let romRecovery = """
            If the FM-1 won't start at all, not even in USB recovery mode, Backup & rescue can usually \
            still reach it through its chip's own download mode, which works even when the firmware \
            is broken: an FM-1 whose firmware is damaged often starts in that mode by itself. From \
            there it can back up the whole flash, put a backup back or write a firmware, and install \
            m-bootloader, so holding REC always gets you back there. M-Flasher, for Mac, Windows and \
            Linux, uses download mode too. The firmware hub keeps a list of rescue tools, with others \
            for an FM-1 that doesn't get that far. FM-SWITCH hasn't tried those.
            """
    #else
        static let romRecovery = """
            If the FM-1 won't start at all, not even in USB recovery mode, FM-SWITCH can't help, but a \
            computer usually can. M-Flasher, for Mac, Windows and Linux, backs up and reinstalls the \
            FM-1 through its chip's own download mode, which works even when the firmware is broken: \
            an FM-1 whose firmware is damaged often starts in that mode by itself. The firmware hub \
            keeps a list of rescue tools, M-Flasher among them, with others for an FM-1 that doesn't \
            get that far. FM-SWITCH hasn't tried any of these.
            """
    #endif

    /// Where to find the computer recovery tools, and why some firmwares need them.
    static let romRecoveryLinks = [
        CatalogueLink(label: "M-Flasher", url: URL(literal: "https://github.com/jvitkauskas/m-flasher")),
        CatalogueLink(
            label: "Rescue tools on the firmware hub",
            url: URL(literal: "https://thefirmwarehub.com/tools/#rescue")
        ),
        CatalogueLink(
            label: "Why some firmwares won't install others",
            url: URL(literal: "https://fm-1.drewr.dev/bootloader-check/")
        ),
    ]
}

/// The first-run notice.
///
/// It has to be acknowledged before the app can be used; OK unlocks after a few seconds, so it
/// isn't tapped away unread.
struct SafetyNoticeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme
    @State private var secondsLeft = 4

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("FM-SWITCH")
                        .font(.pixel(28, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(theme.bright)
                        .phosphorGlow()
                        .padding(.top, 40)
                    PixelPanel(title: "BEFORE YOU START") {
                        MonoText(SafetyNotice.text, size: 16)
                        MonoText(SafetyNotice.recovery, size: 16)
                    }
                    MonoText("This notice is also on the SETUP screen.", size: 13, dim: true)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)

            Button(secondsLeft > 0 ? "OK (\(secondsLeft))" : "OK") {
                model.settings.acknowledgedNoticeVersion = SafetyNotice.version
            }
            .buttonStyle(.pixelProminent)
            .disabled(secondsLeft > 0)
            .padding(20)
        }
        .frame(maxWidth: WideLayout.readableWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .task {
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                secondsLeft -= 1
            }
        }
    }
}
