import FM1Kit

/// What ``DeviceController`` is doing: a flash, a voice restore or a backup, and how far each has got.
extension DeviceController {
    enum FlashPhase: Equatable {
        case preparing
        case staging(requests: Int)
        case waitingForLoader
        case writing(fraction: Double)
        /// The loader's second pass over the image, in which Felucca's loader still writes, so it's
        /// never safe to interrupt; not every loader makes one.
        case secondPass(fraction: Double)
        case rebooting
        case succeeded(String)
        case failed(String, canResume: Bool)

        var label: String {
            switch self {
            case .preparing: "CONNECTING"
            case .staging: "CHECKING PACKAGE"
            case .waitingForLoader: "WAITING FOR LOADER"
            case .writing: "WRITING"
            case .secondPass: "WRITING PASS 2"
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
        /// Whether the person confirmed the FM-1 isn't really running the official firmware it
        /// reports, such as TransitFM1 reporting V15.
        var confirmsReinstallingOfficial = false
        /// The guide to switching away from what the FM-1 is running, as far as the install has
        /// got: what it started from, then each firmware as it goes on.
        var guide: LeavingGuide?
        /// Whether the FM-1 was running V16 when the install started, which leaves V15 playing one
        /// note at a time until its saved data is erased.
        var startedOnV16 = false
        var index = 0
        var phase = FlashPhase.preparing
        /// Whether it stopped because, with the FM-1's bootloader changed, its firmware won't take
        /// this until MIDIMON or LOOM-8 is installed first.
        var needsAStepFirst = false
        /// Whether it stopped before the install started, which might be the FM-1's firmware
        /// refusing it, so trying again might not help.
        var mightBeRefused = false
        /// The most of the firmware the loader has read in this step, which is all of it once it
        /// starts its second pass.
        var writtenFraction = 0.0

        /// How long to look for the FM-1 after an error that can hide a finished install.
        static let returnSearch = Duration.seconds(20)

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

        /// Whether the FM-1 might be running the new firmware after `error`, though FM1Kit didn't see
        /// it come back.
        ///
        /// It might when the loader finished writing but the FM-1 wasn't found again, or when the
        /// write stopped near the end: the loader can restart into the new firmware without saying
        /// it's finished. Only the first counts for a reinstall, as the firmware the FM-1 had reports
        /// the same identity.
        ///
        /// - Parameters:
        ///   - error: Why the install stopped.
        ///   - written: How much of the firmware the loader had read, from 0 to 1.
        ///   - reinstalling: Whether the FM-1 already reported the package's identity.
        /// - Returns: Whether to look for the FM-1 running it.
        static func mightHaveFinished(after error: any Error, written: Double, reinstalling: Bool) -> Bool {
            switch error as? FM1UpdateError {
            case .deviceDidNotReturn: true
            case .stalled(.writing, _), .disconnected(.writing, _): written >= 0.9 && !reinstalling
            default: false
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

        /// Whether `error` is a refusal that only MIDIMON or LOOM-8 gets past, rather than
        /// putting V15 on first: always for V15 itself, and otherwise unless the firmware running
        /// installs V15, as its guide says, or when there's none, as the FM-1's start-up says.
        static func needsAStepFirst(
            after error: any Error,
            installing item: StoredFirmware,
            from running: LeavingGuide?,
            startUp: StartUp?
        ) -> Bool {
            guard isRefusal(error) else { return false }
            guard item.source != .official else { return true }
            if let route = running?.route(to: .v15) { return route != .direct }
            return startUp != .mVave
        }

        /// What went wrong, in words: FM1Kit's, apart from the firmware on the FM-1 refusing the
        /// package, which is said plainly.
        ///
        /// - Parameters:
        ///   - error: Why the install stopped.
        ///   - item: The firmware it was installing.
        ///   - running: The name of the firmware the FM-1 is running, if it's known.
        ///   - needsAStepFirst: Whether only MIDIMON or LOOM-8 gets past the refusal.
        /// - Returns: The message.
        static func failureMessage(
            for error: any Error,
            installing item: StoredFirmware,
            running: String?,
            needsAStepFirst: Bool
        ) -> String {
            guard isRefusal(error) else { return error.localizedDescription }
            let opening = """
                Your FM-1 is fine. It's still running \(running ?? "the firmware it had"), which won't take \
                \(item.name) from here.
                """
            // V15 takes the rest, so going through it gets past a refusal it isn't part of; MIDIMON
            // and LOOM-8 are let in, and their updated check takes the rest (FM1Kit's stage P).
            let first = needsAStepFirst ? "MIDIMON 0.4 or LOOM-8" : "V15"
            return "\(opening) Install \(first) first, then \(item.name)."
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
            case .writing(let fraction), .secondPass(let fraction): fraction
            case .succeeded: 1
            case .preparing, .waitingForLoader, .rebooting, .failed: nil
            }
        }
    }
}
