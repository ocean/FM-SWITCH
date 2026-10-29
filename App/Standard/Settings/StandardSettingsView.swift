import StoreKit
import SwiftUI

/// Settings for the standard look: appearance, the firmware list, the connection, the safety
/// and recovery notes, and the tip jar.
struct StandardSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            appearance
            look
            firmwareList
            files
            connection
            safety
            TipJarSection(tipJar: model.tipJar)
            #if os(macOS)
                updates
            #endif
            about
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .tint(Palette.accent)
        .navigationTitle("Settings")
    }

    private var appearance: some View {
        @Bindable var settings = model.settings
        return Section {
            AppearancePicker(selection: $settings.appearance.animation(Motion.fade))
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            caption("Appearance")
        } footer: {
            caption(appearanceNote)
        }
    }

    /// Standard or Retro, and the app's icon.
    ///
    /// The Easter egg on the home screen still finds Retro; this is the way in for everyone else.
    private var look: some View {
        @Bindable var settings = model.settings
        return Section {
            Picker("Look", selection: $settings.look.animation(Motion.fade)) {
                Text("Standard").tag(Look.standard)
                Text("Retro").tag(Look.retro)
            }
            if AlternateIcon.isAvailable {
                AppIconPicker()
            }
        } footer: {
            caption(
                settings.isRetroFound
                    ? "You found Retro, an 8-bit look for the app. Switch to it here any time."
                    : "Retro is an 8-bit look for the app. There's another way to find it, if you look.")
        }
    }

    private var firmwareList: some View {
        @Bindable var settings = model.settings
        return Section {
            Toggle("Show test versions", isOn: $settings.showBeta)
            Toggle("Show firmwares without a download", isOn: $settings.showLinksOnly)
            Toggle("Always install the official firmware first", isOn: $settings.alwaysViaOfficial)
            Picker("Your FM-1's start-up", selection: $settings.startUp) {
                Text("Ask when it matters").tag(StartUp?.none)
                ForEach(StartUp.allCases) { Text($0.name).tag(Optional($0)) }
            }
        } header: {
            caption("Firmware list")
        }
    }

    /// Where firmwares and backups are kept.
    private var files: some View {
        Section {
            Button {
                SavedFiles.open(model.filesFolder)
            } label: {
                LabeledContent {
                    Text("Open in \(SavedFiles.folderAppName)")
                } label: {
                    Label(
                        model.isUsingICloud ? "In iCloud Drive" : "On this \(ThisDevice.name)",
                        systemImage: model.isUsingICloud ? "icloud" : "internaldrive")
                }
            }
        } header: {
            caption("Firmwares and backups")
        } footer: {
            caption(SharedStorage.whereFilesAre(inICloud: model.isUsingICloud))
        }
    }

    private var safety: some View {
        Section {
            Text(SafetyNotice.text)
            Text(SafetyNotice.recovery)
            Text(SafetyNotice.romRecovery)
            ForEach(SafetyNotice.romRecoveryLinks, id: \.url) { link in
                Link(link.label, destination: link.url)
            }
        } header: {
            caption("Safety and recovery")
        }
        .font(.callout)
    }

    #if os(macOS)
        /// Whether to check GitHub for a newer FM-SWITCH, which the Mac app is downloaded from.
        private var updates: some View {
            @Bindable var updates = model.updates
            return Section {
                Toggle("Check for new versions automatically", isOn: $updates.checksAutomatically)
            } footer: {
                caption("Once a day, FM-SWITCH asks GitHub for its newest version. Nothing about you is sent.")
            }
        }
    #endif

    private var about: some View {
        Section {
            Text(
                """
                Firmware lists: thefirmwarehub.com, fm1-editor.com and aroum's FM1 Resource Hub. \
                Files come from the firmware hub, GitHub releases, publishers' own sites and M-VAVE.
                """
            )
            Text("The update protocol is from the AL-255/FM-1-RE reverse-engineering notes.")
            Text(
                """
                Official firmware: M-VAVE's FM-1 V15, unmodified, from github.com/m-vave/fm1_open under \
                the Apache License 2.0. FM-SWITCH isn't made or endorsed by M-VAVE.
                """
            )
            Text("Retro fonts: Departure Mono, Silkscreen and VT323 (SIL Open Font Licence).")
        } header: {
            caption("About")
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
    }

    /// A section's header or footer.
    ///
    /// The system's grey falls just short of 4.5:1 on the ground, so it's in
    /// ``Palette/secondaryInk``, which `ContrastTests` checks.
    private func caption(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.secondaryInk)
    }

    private var appearanceNote: String {
        switch model.settings.appearance {
        case .system: "Matches your \(ThisDevice.name), which is \(colorScheme == .dark ? "dark" : "light") right now."
        case .light: "Always light, whatever your \(ThisDevice.name) is set to."
        case .dark: "Always dark, whatever your \(ThisDevice.name) is set to."
        }
    }

    @ViewBuilder private var connection: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("Connect to", selection: $settings.transportKind) {
                Text("FM-1 over USB").tag(TransportKind.usbMIDI)
                Text("Simulated FM-1").tag(TransportKind.simulated)
            }
            .onChange(of: settings.transportKind) { model.applyConnectionSettings() }
            if settings.transportKind == .simulated {
                Toggle("Start waiting to finish an install", isOn: $settings.simulatedRecoveryMode)
                Toggle("Pull the cable at 45%", isOn: $settings.simulatedCablePull)
                Toggle("Read backwards, like V15", isOn: $settings.simulatedReadsBackwards)
                Toggle("Check after writing, like Felucca", isOn: $settings.simulatedVerifies)
                Toggle("Has m-bootloader, and refuses M-VAVE's packages", isOn: $settings.simulatedMBootloader)
                    .onChange(of: settings.simulatedMBootloader) { model.applyConnectionSettings() }
                Toggle("Run open firmware, with projects to save", isOn: $settings.simulatedOpenFirmware)
                    // It changes what the FM-1 reports, so it starts again straight away.
                    .onChange(of: settings.simulatedOpenFirmware) { model.applyConnectionSettings() }
                Button("Reset the simulated FM-1") { model.applyConnectionSettings() }
                    .disabled(model.device.isWriting)
            }
        } header: {
            caption("Connection")
        } footer: {
            caption("The simulated FM-1 is for trying the app without one.")
        }
        .disabled(model.device.isWriting)
    }
}

/// Tips as in-app purchases on iPhone and iPad, or a link to Ko-fi on the Mac.
private struct TipJarSection: View {
    @Environment(\.purchase) private var purchase
    let tipJar: TipJar

    var body: some View {
        Section {
            if TipJar.isInApp {
                ForEach(tipJar.tips) { tip in
                    Button {
                        Task { await buy(tip) }
                    } label: {
                        LabeledContent(tip.name) {
                            if tipJar.status == .buying(tip.id) { ProgressView() } else { Text(tip.price) }
                        }
                        .foregroundStyle(Palette.ink)
                    }
                    .disabled(tipJar.status == .buying(tip.id))
                }
                if tipJar.status == .loading { ProgressView().frame(maxWidth: .infinity) }
            } else {
                Link("Leave a tip on Ko-fi", destination: Tips.koFi)
            }
        } header: {
            Text("Tip jar").foregroundStyle(Palette.secondaryInk)
        } footer: {
            Text(footer).foregroundStyle(Palette.secondaryInk)
        }
        .task { await tipJar.load() }
        .sensoryFeedback(.success, trigger: tipJar.status == .thanked)
    }

    /// Buys with SwiftUI's purchase action, which shows the App Store's sheet in this window.
    private func buy(_ tip: Tip) async {
        await tipJar.buy(tip) { try await purchase($0) }
    }

    private var footer: String {
        switch tipJar.status {
        case .thanked: Tips.thanks
        case .failed: Tips.unavailable
        default: Tips.note
        }
    }
}

/// The Home Screen icon: the standard one, or Retro's pixel-art one.
private struct AppIconPicker: View {
    @State private var isRetro = AlternateIcon.isRetro

    var body: some View {
        Picker("App icon", selection: $isRetro) {
            Text("Standard").tag(false)
            Text("Retro").tag(true)
        }
        .onChange(of: isRetro) { _, retro in
            guard retro != AlternateIcon.isRetro else { return }
            Task {
                do {
                    try await AlternateIcon.set(retro: retro)
                } catch {
                    // iOS refused, so show the icon it kept.
                    isRetro = AlternateIcon.isRetro
                }
            }
        }
    }
}

/// Three tiles, System, Light and Dark, each showing what it looks like.
private struct AppearancePicker: View {
    @Binding var selection: Appearance

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Appearance.allCases) { option in
                let isPicked = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 8) {
                        AppearancePreview(appearance: option)
                        Text(option.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isPicked ? Palette.accent : Palette.secondaryInk)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isPicked ? Palette.accent : .clear, lineWidth: 2)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A tiny screen in light, dark, or half of each for System.
private struct AppearancePreview: View {
    private typealias Shades = Palette.Shades
    var appearance: Appearance

    var body: some View {
        HStack(spacing: 0) {
            if appearance != .dark { half(ground: Shades.ground.light, card: Shades.card.light, ink: Shades.ink.light) }
            if appearance != .light { half(ground: Shades.ground.dark, card: Shades.card.dark, ink: Shades.ink.dark) }
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line))
        .accessibilityHidden(true)
    }

    private func half(ground: UInt32, card: UInt32, ink: UInt32) -> some View {
        VStack(spacing: 5) {
            Capsule().fill(Color(rgb: ink)).frame(width: 24, height: 5)
            RoundedRectangle(cornerRadius: 4).fill(Color(rgb: card)).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color(rgb: card)).frame(height: 12)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(rgb: ground))
    }
}
