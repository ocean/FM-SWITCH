import StoreKit
import SwiftUI

/// Look, connection and flashing preferences, plus credits.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.phosphor) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: "SETUP")

                AdaptiveColumns {
                    PixelPanel(title: "SAFETY + RECOVERY") {
                        MonoText(SafetyNotice.text, size: 14)
                        MonoText(SafetyNotice.recovery, size: 14)
                    }

                    PixelPanel(title: "IF IT WON'T START AT ALL") { romRecovery }
                    PixelPanel(title: "TIP JAR") { RetroTipJar(tipJar: model.tipJar) }
                    PixelPanel(title: "CREDITS") { credits }
                } trailing: {
                    PixelPanel(title: "LOOK") {
                        MonoText("You're using Retro. The standard look is the app's everyday one.", size: 14)
                        Button("SWITCH TO STANDARD") { model.settings.look = .standard }
                            .buttonStyle(.pixel)
                        if AlternateIcon.isAvailable { RetroIconButton() }
                    }
                    PixelPanel(title: "COLOUR + SCREEN") { lookSettings }
                    PixelPanel(title: "FIRMWARES + BACKUPS") {
                        MonoText(SharedStorage.whereFilesAre(inICloud: model.isUsingICloud), size: 14)
                        Button("OPEN IN \(SavedFiles.folderAppName.uppercased())") {
                            SavedFiles.open(model.filesFolder)
                        }
                        .buttonStyle(.pixelCompact)
                    }
                    PixelPanel(title: "CONNECTION") { connectionSettings }
                    PixelPanel(title: "FLASHING") { flashingSettings }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Panels.

    @ViewBuilder private var romRecovery: some View {
        MonoText(SafetyNotice.romRecovery, size: 14)
        ForEach(SafetyNotice.romRecoveryLinks, id: \.url) { link in
            PixelLink(link.url) {
                Text("▸ \(link.label.uppercased())")
                    .font(.pixel(11, bold: true, relativeTo: .callout))
                    .foregroundStyle(theme.bright)
            }
        }
    }

    @ViewBuilder private var lookSettings: some View {
        @Bindable var settings = model.settings
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(PhosphorPreset.allCases) { preset in
                presetButton(preset)
            }
        }
        ColorPicker(
            selection: Binding(
                get: { Color(hex: settings.phosphorHex) ?? PhosphorPreset.green.colour },
                set: { settings.phosphorHex = $0.hexString }
            ),
            supportsOpacity: false
        ) {
            MonoText("CUSTOM COLOUR  \(settings.phosphorHex)", size: 14)
        }
        labelledSlider("GLOW", value: $settings.glow)
        Button("RESET LOOK") { settings.resetLook() }
            .buttonStyle(.pixelCompact)
        PixelToggle("CRT SCANLINES", isOn: $settings.scanlines)
        PixelToggle("CRT FLICKER", isOn: $settings.flicker)
    }

    @ViewBuilder private var connectionSettings: some View {
        @Bindable var settings = model.settings
        HStack(spacing: 8) {
            ForEach(TransportKind.allCases) { kind in
                Button(kind.name) {
                    settings.transportKind = kind
                    model.applyConnectionSettings()
                }
                .buttonStyle(PixelButtonStyle(prominent: settings.transportKind == kind, compact: true))
            }
        }
        #if targetEnvironment(simulator)
            NoteText(
                """
                The iOS Simulator can't reach USB devices plugged into the Mac, so use the simulated FM-1 \
                here, or run on a phone, an iPad or the Mac.
                """
            )
        #endif
        if settings.transportKind == .simulated {
            PixelToggle("START IN USB RECOVERY MODE", isOn: $settings.simulatedRecoveryMode)
            PixelToggle("PULL THE CABLE AT 45%", isOn: $settings.simulatedCablePull)
            PixelToggle("READ BACKWARDS, LIKE V15", isOn: $settings.simulatedReadsBackwards)
            PixelToggle("VERIFY AFTER WRITING, LIKE FELUCCA", isOn: $settings.simulatedVerifies)
            PixelToggle("M-BOOTLOADER, REFUSES M-VAVE'S", isOn: $settings.simulatedMBootloader)
            PixelToggle("RUN OPEN FIRMWARE, WITH PROJECTS", isOn: $settings.simulatedOpenFirmware)
            Button("RESET SIMULATED FM-1") { model.applyConnectionSettings() }
                .buttonStyle(.pixel)
                .disabled(model.device.isWriting)
        }
    }

    @ViewBuilder private var flashingSettings: some View {
        @Bindable var settings = model.settings
        PixelToggle("ALWAYS VIA OFFICIAL FIRMWARE", isOn: $settings.alwaysViaOfficial)
        NoteText("Off: the official firmware is only flashed first when a firmware needs it.")
        MonoText("YOUR FM-1'S START-UP", size: 14)
        ForEach(StartUp.allCases) { StartUpChoice(choice: $0, startUp: $settings.startUp) }
        NoteText("Asked before installing a firmware that can't go back to V15 from here with m-bootloader.")
        PixelToggle("SHOW BETA FIRMWARES", isOn: $settings.showBeta)
        PixelToggle("SHOW LINKS-ONLY FIRMWARES", isOn: $settings.showLinksOnly)
        NoteText("Links-only firmwares have no file this app can download; they link to their own sites.")
    }

    @ViewBuilder private var credits: some View {
        NoteText(
            """
            Firmware lists: thefirmwarehub.com (mirrors each project's GitHub releases) and \
            fm1-editor.com/firmware. Packages come from the hub, GitHub releases, publishers' own sites, \
            and M-VAVE.
            """
        )
        NoteText("Update protocol: written from the AL-255/FM-1-RE reverse-engineering notes.")
        NoteText(
            """
            Official firmware: M-VAVE's FM-1 V15, unmodified, from github.com/m-vave/fm1_open under \
            the Apache License 2.0 (apache.org/licenses/LICENSE-2.0). FM-SWITCH isn't made or \
            endorsed by M-VAVE.
            """
        )
        NoteText("Fonts: Departure Mono, Silkscreen and VT323 (SIL Open Font Licence).")
    }

    // MARK: - Controls.

    private func presetButton(_ preset: PhosphorPreset) -> some View {
        let selected = model.settings.phosphorHex.uppercased() == preset.hex
        return Button {
            model.settings.phosphorHex = preset.hex
        } label: {
            VStack(spacing: 4) {
                Rectangle().fill(preset.colour).frame(height: 18)
                Text(preset.name).font(.pixel(8, bold: true, relativeTo: .caption2))
            }
            .padding(6)
            .foregroundStyle(theme.bright)
            .overlay(PixelBox(step: 2).strokeBorder(selected ? theme.bright : theme.faint, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func labelledSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            MonoText(title, size: 14)
            Slider(value: value, in: 0...1)
                .tint(theme.bright)
        }
    }
}

/// Tips as in-app purchases on iPhone and iPad, or a link to Ko-fi on the Mac.
struct RetroTipJar: View {
    @Environment(\.phosphor) private var theme
    @Environment(\.purchase) private var purchase
    let tipJar: TipJar
    /// What it says under the tips, until one's bought.
    var message = Tips.note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if TipJar.isInApp {
                HStack(spacing: 8) {
                    ForEach(tipJar.tips) { tip in
                        Button {
                            Task { await buy(tip) }
                        } label: {
                            VStack(spacing: 4) {
                                Text(tip.name.uppercased())
                                Text(tipJar.status == .buying(tip.id) ? "…" : tip.price)
                            }
                        }
                        .buttonStyle(.pixelCompact)
                        .accessibilityLabel("\(tip.name), \(tip.price)")
                        .disabled(tipJar.status == .buying(tip.id))
                    }
                }
                if tipJar.status == .loading { NoteText("LOADING TIPS…") }
            } else {
                PixelLink(Tips.koFi) {
                    Text("▸ LEAVE A TIP ON KO-FI")
                        .font(.pixel(11, bold: true, relativeTo: .callout))
                        .foregroundStyle(theme.bright)
                }
            }
            NoteText(note)
        }
        .task { await tipJar.load() }
        .sensoryFeedback(.success, trigger: tipJar.status == .thanked)
    }

    /// Buys with SwiftUI's purchase action, which shows the App Store's sheet in this window.
    private func buy(_ tip: Tip) async {
        await tipJar.buy(tip) { try await purchase($0) }
    }

    private var note: String {
        switch tipJar.status {
        case .thanked: Tips.thanks
        case .failed: Tips.unavailable
        default: message
        }
    }
}

/// Switches the Home Screen icon between Retro's pixel-art one and the standard one.
private struct RetroIconButton: View {
    @State private var isRetro = AlternateIcon.isRetro

    var body: some View {
        Button(isRetro ? "USE STANDARD ICON" : "USE PIXEL ICON") {
            Task {
                // iOS tells the person the icon has changed, or keeps the old one if it refuses.
                try? await AlternateIcon.set(retro: !isRetro)
                isRetro = AlternateIcon.isRetro
            }
        }
        .buttonStyle(.pixelCompact)
    }
}
