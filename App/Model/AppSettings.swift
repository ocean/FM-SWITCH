import Foundation
import Observation
import SwiftUI

enum TransportKind: String, CaseIterable, Identifiable {
    /// A real FM-1 over USB through CoreMIDI.
    case usbMIDI
    /// The software FM-1, for the Simulator and demos.
    case simulated

    var id: String { rawValue }

    var name: String {
        switch self {
        case .usbMIDI: "USB MIDI"
        case .simulated: "SIMULATED FM-1"
        }
    }
}

/// The app's two looks: the standard one, and the 8-bit one found by tapping the FM-1's screen.
enum Look: String, CaseIterable, Identifiable {
    case standard
    case retro

    var id: String { rawValue }
}

/// Light or dark for the standard look, or whichever the device is using.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The scheme to ask for, or nil to follow the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var look: Look { didSet { defaults.set(look.rawValue, forKey: Keys.look) } }
    /// Whether Retro has been found, which puts it in Settings from then on.
    var isRetroFound: Bool { didSet { defaults.set(isRetroFound, forKey: Keys.isRetroFound) } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var phosphorHex: String { didSet { defaults.set(phosphorHex, forKey: Keys.phosphorHex) } }
    var glow: Double { didSet { defaults.set(glow, forKey: Keys.glow) } }
    var scanlines: Bool { didSet { defaults.set(scanlines, forKey: Keys.scanlines) } }
    var flicker: Bool { didSet { defaults.set(flicker, forKey: Keys.flicker) } }
    var transportKind: TransportKind { didSet { defaults.set(transportKind.rawValue, forKey: Keys.transport) } }
    var showBeta: Bool { didSet { defaults.set(showBeta, forKey: Keys.showBeta) } }
    /// List firmwares with no downloadable file (their links are still useful), off by default
    /// so the list only offers what can actually be flashed.
    var showLinksOnly: Bool { didSet { defaults.set(showLinksOnly, forKey: Keys.showLinksOnly) } }
    /// Install the official firmware first on every swap, not only when a firmware requires it.
    var alwaysViaOfficial: Bool { didSet { defaults.set(alwaysViaOfficial, forKey: Keys.alwaysViaOfficial) } }
    /// What the person says starts their FM-1, or nil until they've been asked.
    var startUp: StartUp? { didSet { defaults.set(startUp?.rawValue, forKey: Keys.startUp) } }
    var simulatedRecoveryMode: Bool { didSet { defaults.set(simulatedRecoveryMode, forKey: Keys.simulatedRecovery) } }
    var simulatedCablePull: Bool { didSet { defaults.set(simulatedCablePull, forKey: Keys.simulatedCablePull) } }
    /// The simulated loader reads the image from the end, as M-VAVE's V15 loader does.
    var simulatedReadsBackwards: Bool {
        didSet { defaults.set(simulatedReadsBackwards, forKey: Keys.simulatedReadsBackwards) }
    }
    /// The simulated loader reads the image again after writing it, as Felucca's loader does.
    var simulatedVerifies: Bool { didSet { defaults.set(simulatedVerifies, forKey: Keys.simulatedVerifies) } }
    /// The simulated FM-1 has m-bootloader and runs a Felucca-based firmware, so it refuses M-VAVE's
    /// packages.
    var simulatedMBootloader: Bool {
        didSet { defaults.set(simulatedMBootloader, forKey: Keys.simulatedMBootloader) }
    }
    /// The simulated FM-1 runs M-VAVE's open firmware, with projects and samples to save.
    var simulatedOpenFirmware: Bool {
        didSet { defaults.set(simulatedOpenFirmware, forKey: Keys.simulatedOpenFirmware) }
    }
    /// The `SafetyNotice.version` the user last acknowledged (0 for never).
    var acknowledgedNoticeVersion: Int {
        didSet { defaults.set(acknowledgedNoticeVersion, forKey: Keys.acknowledgedNotice) }
    }

    /// How many tip cards have been shown, so each shows once.
    var tipNudgesShown: Int { didSet { defaults.set(tipNudgesShown, forKey: Keys.tipNudgesShown) } }

    var needsSafetyNotice: Bool { acknowledgedNoticeVersion < SafetyNotice.version }

    /// Bumped when the look's defaults change, so earlier saved look settings are dropped once.
    private static let lookVersion = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.integer(forKey: Keys.lookVersion) < Self.lookVersion {
            for key in [Keys.phosphorHex, Keys.glow, Keys.scanlines, Keys.flicker] {
                defaults.removeObject(forKey: key)
            }
            defaults.set(Self.lookVersion, forKey: Keys.lookVersion)
        }
        let savedLook = Self.savedLook(in: defaults)
        look = savedLook
        isRetroFound = defaults.bool(forKey: Keys.isRetroFound) || savedLook == .retro
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        let standard = PhosphorTheme.standard
        phosphorHex = defaults.string(forKey: Keys.phosphorHex) ?? PhosphorPreset.green.hex
        glow = defaults.object(forKey: Keys.glow) as? Double ?? standard.glow
        scanlines = defaults.object(forKey: Keys.scanlines) as? Bool ?? standard.scanlines
        flicker = defaults.object(forKey: Keys.flicker) as? Bool ?? standard.flicker
        #if targetEnvironment(simulator)
            let defaultTransport = TransportKind.simulated
        #else
            let defaultTransport = TransportKind.usbMIDI
        #endif
        transportKind =
            defaults.string(forKey: Keys.transport).flatMap(TransportKind.init(rawValue:)) ?? defaultTransport
        showBeta = defaults.object(forKey: Keys.showBeta) as? Bool ?? true
        showLinksOnly = defaults.object(forKey: Keys.showLinksOnly) as? Bool ?? false
        alwaysViaOfficial = defaults.object(forKey: Keys.alwaysViaOfficial) as? Bool ?? false
        startUp = defaults.string(forKey: Keys.startUp).flatMap(StartUp.init(rawValue:))
        simulatedRecoveryMode = defaults.object(forKey: Keys.simulatedRecovery) as? Bool ?? false
        simulatedCablePull = defaults.object(forKey: Keys.simulatedCablePull) as? Bool ?? false
        simulatedReadsBackwards = defaults.object(forKey: Keys.simulatedReadsBackwards) as? Bool ?? false
        simulatedVerifies = defaults.object(forKey: Keys.simulatedVerifies) as? Bool ?? false
        simulatedMBootloader = defaults.bool(forKey: Keys.simulatedMBootloader)
        // `bool(forKey:)` reads `-simulatedOpenFirmware YES` too, for UI tests.
        simulatedOpenFirmware = defaults.bool(forKey: Keys.simulatedOpenFirmware)
        acknowledgedNoticeVersion = defaults.integer(forKey: Keys.acknowledgedNotice)
        tipNudgesShown = defaults.integer(forKey: Keys.tipNudgesShown)
    }

    /// The look last picked, read straight from `defaults`.
    static func savedLook(in defaults: UserDefaults = .standard) -> Look {
        defaults.string(forKey: Keys.look).flatMap(Look.init(rawValue:)) ?? .standard
    }

    /// Puts the colour and screen effects back to the defaults.
    func resetLook() {
        let standard = PhosphorTheme.standard
        phosphorHex = PhosphorPreset.green.hex
        glow = standard.glow
        scanlines = standard.scanlines
        flicker = standard.flicker
    }

    var theme: PhosphorTheme {
        PhosphorTheme(
            base: Color(hex: phosphorHex) ?? PhosphorPreset.green.colour,
            glow: glow,
            scanlines: scanlines,
            flicker: flicker
        )
    }

    private enum Keys {
        static let look = "look"
        static let isRetroFound = "isRetroFound"
        static let appearance = "appearance"
        static let lookVersion = "lookVersion"
        static let phosphorHex = "phosphorHex"
        static let glow = "glow"
        static let scanlines = "scanlines"
        static let flicker = "flicker"
        static let transport = "transport"
        static let showBeta = "showBeta"
        static let showLinksOnly = "showLinksOnly"
        static let alwaysViaOfficial = "alwaysViaOfficial"
        static let startUp = "startUp"
        static let simulatedRecovery = "simulatedRescueMode"  // The original key, so saved settings carry over.
        static let simulatedCablePull = "simulatedCablePull"
        static let simulatedReadsBackwards = "simulatedReadsBackwards"
        static let simulatedVerifies = "simulatedVerifies"
        static let simulatedMBootloader = "simulatedMBootloader"
        static let simulatedOpenFirmware = "simulatedOpenFirmware"
        static let acknowledgedNotice = "acknowledgedNoticeVersion"
        static let tipNudgesShown = "tipNudgesShown"
    }
}
