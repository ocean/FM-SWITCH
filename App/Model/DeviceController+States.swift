import FM1Kit

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
        /// Whether it stopped because, with the FM-1's bootloader changed, its firmware won't take
        /// this until MIDIMON or LOOM-8 is installed first.
        var needsAStepFirst = false
        /// Whether it stopped before the install started, which might be the FM-1's firmware
        /// refusing it, so trying again might not help.
        var mightBeRefused = false

        var current: StoredFirmware { steps[index] }

        /// Whether the FM-1 is left waiting in its loader after `error`, so the install can carry on.
        static func canResume(after error: any Error) -> Bool {
            switch error as? FM1UpdateError {
            case .disconnected(.writing, _), .stalled(.writing, _), .loaderNotFound:
                true
            default:
                false
            }
        }

        /// Whether the installed firmware refused the package: one built on Felucca's earlier
        /// update code, once the FM-1's bootloader has been changed, or one on Felucca 1.6.1
        /// refusing Open.
        static func isRefusal(_ error: any Error) -> Bool {
            switch error as? FM1UpdateError {
            case .bootloaderMismatch, .packageRefused: true
            default: false
            }
        }

        /// Whether `error` might be the installed firmware refusing the package before it checks
        /// the bootloader, which FM1Kit can't tell apart from the install not starting.
        static func mightBeRefused(after error: any Error) -> Bool {
            guard case .stalled(.staging, _) = error as? FM1UpdateError else { return false }
            return true
        }

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
