/// What ``DeviceController`` is doing: a flash, a voice restore or a backup, and how far each has got.
extension DeviceController {
    enum FlashPhase: Equatable {
        case preparing
        case staging(requests: Int)
        case waitingForLoader
        case writing(fraction: Double)
        /// The loader reading back what it wrote; not every loader does this.
        case verifying(fraction: Double)
        case rebooting
        case succeeded(String)
        case failed(String, canResume: Bool)

        var label: String {
            switch self {
            case .preparing: "CONNECTING"
            case .staging: "CHECKING PACKAGE"
            case .waitingForLoader: "WAITING FOR LOADER"
            case .writing: "WRITING"
            case .verifying: "VERIFYING"
            case .rebooting: "REBOOTING"
            case .succeeded: "DONE"
            case .failed: "STOPPED"
            }
        }
    }

    /// Restoring V15's factory voices, which M-VAVE's updater offers after installing V15.
    enum VoiceRestore: Equatable {
        case idle
        case writing(fraction: Double)
        case succeeded
        case failed(String)

        var isRunning: Bool {
            if case .writing = self { true } else { false }
        }
    }

    /// Saving the projects and samples of an FM-1 running M-VAVE's open firmware.
    enum BackupRun: Equatable {
        case idle
        case saving(fraction: Double)
        case succeeded(SavedBackup)
        case failed(String)

        var isRunning: Bool {
            if case .saving = self { true } else { false }
        }
    }

    struct FlashJob: Equatable {
        var steps: [StoredFirmware]
        /// Whether the person confirmed that these steps switch the FM-1 to a different firmware,
        /// which can erase its projects and samples.
        var confirmsSwitchingFirmware = false
        /// Whether the person confirmed installing the identity a custom firmware already reports:
        /// a reinstall, or another release of the same firmware.
        var confirmsSameIdentity = false
        var index = 0
        var phase = FlashPhase.preparing

        var current: StoredFirmware { steps[index] }

        var isRunning: Bool {
            switch phase {
            case .succeeded, .failed: false
            default: true
            }
        }

        /// How far the current phase has got, or `nil` while it can't be measured.
        ///
        /// Each phase counts from 0 on its own: whether a loader verifies after writing isn't known
        /// until it starts, so one bar across every phase would have to jump back. Some loaders
        /// don't read the whole image, so writing can end short of 1.
        var phaseFraction: Double? {
            switch phase {
            case .staging(let requests): min(Double(requests) / 75, 1)
            case .writing(let fraction), .verifying(let fraction): fraction
            case .succeeded: 1
            case .preparing, .waitingForLoader, .rebooting, .failed: nil
            }
        }
    }
}
