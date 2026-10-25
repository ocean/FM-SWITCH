import FM1Kit
import Foundation
import Observation
import SwiftUI

#if os(macOS)
    import FM1Rescue
#endif

/// Talks to the FM-1: identifies it, watches for it coming and going, and runs flashes,
/// including "official first, then the target" chains and resuming interrupted writes.
@MainActor
@Observable
final class DeviceController {
    private(set) var identity: FM1Identity?
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var ports: [MIDIPortDescriptor] = []
    private(set) var job: FlashJob?
    private(set) var voiceRestore = VoiceRestore.idle
    private(set) var backupRun = BackupRun.idle
    private(set) var log: [String] = []
    private(set) var transportName = ""
    private(set) var transportError: String?

    private(set) var transport: any MIDITransport = UnavailableTransport()
    private var updater = FM1Updater(transport: UnavailableTransport())
    private var watchTask: Task<Void, Never>?
    private let wakeKeeper = WakeKeeper()

    private let library: FirmwareLibrary
    private let history: FlashHistory
    /// The person's settings, for what they've said starts their FM-1.
    private var settings: AppSettings?

    init(library: FirmwareLibrary, history: FlashHistory) {
        self.library = library
        self.history = history
    }

    var isFlashing: Bool { job?.isRunning ?? false }

    /// Whether the FM-1 is busy, so nothing else may talk to it.
    ///
    /// It's busy during a flash, a voice restore or a backup. A backup doesn't write a project
    /// slot or the sample bank, but it does load each project in turn.
    var isWriting: Bool { isFlashing || voiceRestore.isRunning || backupRun.isRunning }

    var simulatedDevice: SimulatedFM1? { transport as? SimulatedFM1 }

    // MARK: - Transport.

    func configure(_ kind: TransportKind, settings: AppSettings) {
        guard !isWriting else { return }
        self.settings = settings
        watchTask?.cancel()
        transportError = nil
        switch kind {
        case .usbMIDI:
            do {
                transport = try CoreMIDITransport()
            } catch {
                transport = UnavailableTransport()
                transportError = error.localizedDescription
            }
        case .simulated:
            var options = SimulatedFM1.Options()
            options.startsInRecoveryMode = settings.simulatedRecoveryMode
            options.unplugDuringWriteAt = settings.simulatedCablePull ? 0.45 : nil
            options.writesBackwards = settings.simulatedReadsBackwards
            options.checksAfterWriting = settings.simulatedVerifies
            if settings.simulatedMBootloader {
                options.bootloaderVersion = "1.2"
                options.comparesBootArea = true
            }
            if settings.simulatedOpenFirmware { SimulatedOpenFirmware.apply(to: &options) }
            transport = SimulatedFM1(options: options)
        }
        transportName = kind.name
        updater = FM1Updater(transport: transport)
        identity = nil
        ports = []

        let changes = transport.changes()
        watchTask = Task { [weak self] in
            await self?.scan()
            for await _ in changes {
                // Let a burst of add/remove notifications settle before probing.
                try? await Task.sleep(for: .milliseconds(400))
                // The FM-1 reboots during an install, so a change seen then is checked once it's done.
                while self?.isWriting == true {
                    try? await Task.sleep(for: .seconds(1))
                }
                guard let self else { return }
                await scan()
            }
        }
    }

    // MARK: - Identifying.

    func scan() async {
        guard !isScanning, !isWriting else { return }
        isScanning = true
        defer {
            isScanning = false
            lastScan = .now
        }
        ports = await transport.ports()
        identity = await updater.identify()
        // An FM-1 that's just been plugged in, or has just rebooted, can show up a moment before
        // it answers.
        var retries = 3
        while identity == nil, !ports.isEmpty, retries > 0, !Task.isCancelled {
            retries -= 1
            try? await Task.sleep(for: .seconds(1))
            ports = await transport.ports()
            identity = await updater.identify()
        }
    }

    // MARK: - Flashing.

    /// The steps for installing `target`: the official firmware first when it is required
    /// (or always, if the user prefers) and the device is not already running it.
    func plan(for target: StoredFirmware, requiresOfficial: Bool, alwaysViaOfficial: Bool) -> [StoredFirmware] {
        guard target.source != .official,
            requiresOfficial || alwaysViaOfficial,
            let official = library.official,
            identity?.text != official.product
        else {
            return [target]
        }
        return [official, target]
    }

    /// What installing `item` on the connected FM-1 would do, sending only the handshake (and,
    /// for M-VAVE's open firmware, its capability query).
    func check(_ item: StoredFirmware) async throws -> InstallCheck {
        let package = try await library.loadPackage(item)
        return try await updater.check(package)
    }

    /// Starts installing `steps` in order.
    ///
    /// - Parameters:
    ///   - steps: The firmwares to install, in order.
    ///   - confirmsSwitchingFirmware: Set once the person has confirmed a switch to a different
    ///     firmware; FM1Kit refuses one otherwise.
    ///   - confirmsSameIdentity: Set once the person has confirmed installing the identity a
    ///     custom firmware already reports; FM1Kit refuses one otherwise.
    func flash(_ steps: [StoredFirmware], confirmsSwitchingFirmware: Bool = false, confirmsSameIdentity: Bool = false) {
        guard !steps.isEmpty, !isWriting else { return }
        log = []
        job = FlashJob(
            steps: steps,
            confirmsSwitchingFirmware: confirmsSwitchingFirmware,
            confirmsSameIdentity: confirmsSameIdentity
        )
        Task { await run(from: 0) }
    }

    /// Carries on from the step that stopped; the loader picks up a write where it was interrupted.
    func resume() {
        guard let index = job?.index, job?.isRunning == false else { return }
        job?.phase = .preparing
        Task { await run(from: index) }
    }

    func dismissFlash() {
        guard !isFlashing else { return }
        job = nil
        Task { await scan() }
    }

    private func run(from startIndex: Int) async {
        guard let steps = job?.steps else { return }
        let options = InstallOptions(
            confirmsSwitchingFirmware: job?.confirmsSwitchingFirmware ?? false,
            confirmsSameIdentity: job?.confirmsSameIdentity ?? false
        )
        setKeepAwake(true)
        defer { setKeepAwake(false) }

        for index in startIndex..<steps.count {
            job?.index = index
            job?.phase = .preparing
            let item = steps[index]
            appendLog("▸ \(item.name) \(item.version) (\(item.product))")
            do {
                let package = try await library.loadPackage(item)
                simulatedDevice?.prepare(for: package)

                let (events, continuation) = AsyncStream<UpdateEvent>.makeStream()
                let consumer = Task { @MainActor [weak self] in
                    for await event in events {
                        self?.apply(event)
                    }
                }
                let isLoaderRunning = await updater.identify()?.isLoader ?? false
                let result: Result<FM1Identity, any Error>
                do {
                    let report: @Sendable (UpdateEvent) -> Void = { continuation.yield($0) }
                    result = .success(
                        isLoaderRunning
                            ? try await updater.resume(package, events: report)
                            : try await updater.install(package, options: options, events: report))
                } catch {
                    result = .failure(error)
                }
                continuation.finish()
                await consumer.value

                let installed = try result.get()
                identity = installed
                history.record(item)
            } catch {
                appendLog("✕ \(error.localizedDescription)")
                job?.phase = .failed(failureMessage(for: error, installing: item), canResume: Self.isResumable(error))
                return
            }
        }
        job?.phase = .succeeded(identity?.text ?? "")
        appendLog("✓ Finished.")
    }

    private func apply(_ event: UpdateEvent) {
        switch event {
        case .connected(let identity):
            appendLog("Connected: \(identity.text)")
        case .staging(let requests):
            job?.phase = .staging(requests: requests)
        case .waitingForLoader:
            job?.phase = .waitingForLoader
            appendLog("Package accepted; rebooting into the update loader.")
        case .loaderFound(let identity):
            appendLog("Loader: \(identity.text)")
        case .writing(let fraction, _):
            job?.phase = .writing(fraction: fraction)
        case .checking(let fraction, _):
            if case .verifying = job?.phase {} else { appendLog("Written; the loader is reading it back to check it.") }
            job?.phase = .verifying(fraction: fraction)
        case .rebooting:
            job?.phase = .rebooting
            appendLog("Rebooting into the new firmware.")
        case .finished(let identity):
            appendLog("Device reports \(identity.text).")
        }
    }

    // MARK: - Factory voices.

    /// Erases the FM-1's four voice banks and writes V15's 128 factory voices from the official
    /// firmware, if the FM-1 is running V15.
    ///
    /// Every voice in the banks is replaced, including the person's own, and V15 can't read
    /// them back first, so ask before calling this. If it's interrupted, running it again fixes it.
    func restoreFactoryVoices() async {
        guard !isWriting else { return }
        voiceRestore = .writing(fraction: 0)
        setKeepAwake(true)
        defer { setKeepAwake(false) }
        do {
            guard let official = library.official else { throw FM1UpdateError.factoryVoicesUnavailable }
            let package = try await library.loadPackage(official)
            let (fractions, continuation) = AsyncStream<Double>.makeStream()
            let consumer = Task { @MainActor [weak self] in
                for await fraction in fractions {
                    self?.voiceRestore = .writing(fraction: fraction)
                }
            }
            let result: Result<Void, any Error>
            do {
                try await updater.restoreFactoryVoices(from: package) { continuation.yield($0) }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            continuation.finish()
            await consumer.value
            try result.get()
            voiceRestore = .succeeded
        } catch {
            voiceRestore = .failed(error.localizedDescription)
        }
    }

    #if os(macOS)
        /// Asks the connected FM-1 to restart into the chip's USB download mode, and waits for it
        /// to appear there.
        ///
        /// V15 and Felucca restart on the request; other firmwares may ignore it. Nothing is
        /// written: switching the FM-1 off and on starts its firmware again.
        func enterDownloadMode() async throws {
            guard !isWriting else { return }
            try await updater.enterDownloadMode()
        }
    #endif

    func dismissVoiceRestore() {
        guard !voiceRestore.isRunning else { return }
        voiceRestore = .idle
    }

    // MARK: - Backing up.

    /// Saves the projects and samples of an FM-1 running M-VAVE's open firmware into `store`.
    ///
    /// While it runs, the FM-1 loads each project in turn, then goes back to the one being edited,
    /// unsaved changes and all. No project slot or sample is changed.
    func backUp(into store: BackupStore) async {
        guard !isWriting else { return }
        backupRun = .saving(fraction: 0)
        setKeepAwake(true)
        defer { setKeepAwake(false) }
        let (fractions, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task { @MainActor [weak self] in
            for await fraction in fractions {
                self?.backupRun = .saving(fraction: fraction)
            }
        }
        let result: Result<OpenFirmwareBackup, any Error>
        do {
            result = .success(try await updater.backUpOpenFirmware { continuation.yield($0) })
        } catch {
            result = .failure(error)
        }
        continuation.finish()
        await consumer.value
        do {
            backupRun = .succeeded(try store.save(try result.get()))
        } catch {
            backupRun = .failed(error.localizedDescription)
        }
    }

    func dismissBackup() {
        guard !backupRun.isRunning else { return }
        backupRun = .idle
    }

    /// What went wrong, in words: FM1Kit's, apart from a refusal that only a Mac gets past, which
    /// is said plainly.
    private func failureMessage(for error: any Error, installing item: StoredFirmware) -> String {
        guard case .bootloaderMismatch = error as? FM1UpdateError else { return error.localizedDescription }
        let running = identity.flatMap { history.lastInstall(matching: $0.text)?.name } ?? "the firmware it had"
        // With M-VAVE's start-up these firmwares still take V15, so going through it gets past them.
        if settings?.startUp == .mVave, item.source != .official {
            return """
                Your FM-1 is fine. It's still running \(running), which won't take \(item.name) from here. \
                Install V15 first, then \(item.name).
                """
        }
        return """
            Your FM-1 is fine. It's still running \(running), which won't take \(item.name) while \
            m-bootloader is on it. To put \(item.name) back, use FM-SWITCH on a Mac.
            """
    }

    private static func isResumable(_ error: any Error) -> Bool {
        switch error as? FM1UpdateError {
        case .disconnected(.writing, _), .stalled(.writing, _), .loaderNotFound:
            true
        default:
            false
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
    }

    // MARK: - Staying alive.

    /// Keeps the device awake for the whole flash, restore or backup, so the person only has to
    /// stay in the app.
    private func setKeepAwake(_ on: Bool) {
        wakeKeeper.isHolding = on
    }

    /// Passes on scene changes, so a write that's under way can ask for time to finish.
    func scenePhaseChanged(to phase: ScenePhase) {
        wakeKeeper.scenePhaseChanged(to: phase, isWriting: isWriting)
    }
}

/// Stands in when CoreMIDI could not start; it never finds anything.
final class UnavailableTransport: MIDITransport {
    func ports() async -> [MIDIPortDescriptor] { [] }

    func open(_: MIDIPortDescriptor) async throws -> any MIDIConnection {
        throw MIDITransportError.portGone
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }
}
