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
    /// Every device that answered, when more than one did, so the person can choose one.
    private(set) var devices: [FM1DeviceSummary] = []
    /// The device chosen when more than one is connected, which everything here works with alone.
    private(set) var chosenDevice: FM1DeviceSummary?
    /// The flash chip's JEDEC ID, when the FM-1's firmware reports it, as only some do.
    private(set) var flashChipID: UInt32?
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var ports: [MIDIPortDescriptor] = []
    private(set) var job: FlashJob?
    /// What the voice restore and the backup are doing; only DeviceController+Restoring sets them.
    var voiceRestore = VoiceRestore.idle
    var backupRun = BackupRun.idle
    private(set) var log: [String] = []
    /// Where the install's log is saved as it goes, if it can be.
    private var logFile: InstallLogFile?
    /// The folder installs' logs are saved in, or `nil` to save none, as in tests.
    private let logFolder: URL?
    private(set) var transportName = ""
    private(set) var transportError: String?

    private(set) var transport: any MIDITransport = UnavailableTransport()
    private(set) var updater = FM1Updater(transport: UnavailableTransport())
    private var watchTask: Task<Void, Never>?
    private let wakeKeeper = WakeKeeper()

    let library: FirmwareLibrary
    let history: FlashHistory
    /// The person's settings, for what they've said starts their FM-1.
    private(set) var settings: AppSettings?

    init(library: FirmwareLibrary, history: FlashHistory, logFolder: URL? = nil) {
        self.library = library
        self.history = history
        self.logFolder = logFolder
    }

    var isFlashing: Bool { job?.isRunning ?? false }

    /// Whether the FM-1 is busy, so nothing else may talk to it.
    ///
    /// It's busy during a flash, a voice restore or a backup. A backup doesn't write a project
    /// slot or the sample bank, but it does load each project in turn.
    var isWriting: Bool { isFlashing || voiceRestore.isRunning || backupRun.isRunning }

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
            transport = SimulatedPair.transport(for: settings)
        }
        transportName = kind.name
        updater = FM1Updater(transport: transport)
        identity = nil
        flashChipID = nil
        devices = []
        chosenDevice = nil
        ports = []

        let changes = transport.changes()
        watchTask = Task { [weak self] in
            await self?.scan()
            // On the Mac, CoreMIDI can take a few seconds after launch to list an FM-1 that was
            // already plugged in, and doesn't announce it as a change.
            for _ in 0..<5 where self?.identity == nil && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.scan()
            }
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
        await findDevices()
        // An FM-1 that's just been plugged in, or has just rebooted, can show up a moment before
        // it answers.
        var retries = 3
        while identity == nil, !needsChoice, !ports.isEmpty, retries > 0, !Task.isCancelled {
            retries -= 1
            try? await Task.sleep(for: .seconds(1))
            ports = await transport.ports()
            await findDevices()
        }
    }

    /// Works with `device` alone, of the ones connected.
    func choose(_ device: FM1DeviceSummary) {
        guard !isWriting, devices.contains(device) else { return }
        chosenDevice = device
        updater = FM1Updater(transport: transport, device: device)
        identity = device.identity
        flashChipID = device.flashChipID
    }

    /// Lists the devices connected, and when there's more than one, keeps working with the one
    /// chosen, if it's still there.
    private func findDevices() async {
        let found = await FM1Updater(transport: transport).devices()
        devices = found.count > 1 ? found : []
        chosenDevice = chosenDevice.flatMap { DeviceChoice.same($0, in: devices, identity: identity) }
        updater = FM1Updater(transport: transport, device: chosenDevice)
        let current = devices.isEmpty ? found.first : chosenDevice
        identity = current?.identity
        flashChipID = current?.flashChipID
    }

    // MARK: - Flashing.

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
    ///   - confirmsReinstallingOfficial: Set once the person has confirmed the FM-1 isn't really
    ///     running the official firmware it reports, such as TransitFM1 reporting V15.
    ///   - startedOnV16: Set when carrying on from an install that started on V16.
    func flash(
        _ steps: [StoredFirmware],
        confirmsSwitchingFirmware: Bool = false,
        confirmsSameIdentity: Bool = false,
        confirmsReinstallingOfficial: Bool = false,
        startedOnV16: Bool = false
    ) {
        guard !steps.isEmpty, !isWriting else { return }
        log = []
        logFile = logFolder.flatMap { InstallLogFile(in: $0) }
        job = FlashJob(
            steps: steps,
            confirmsSwitchingFirmware: confirmsSwitchingFirmware,
            confirmsSameIdentity: confirmsSameIdentity,
            confirmsReinstallingOfficial: confirmsReinstallingOfficial,
            guide: runningGuide,
            startedOnV16: startedOnV16 || identity == .officialV16
        )
        Task { await run(from: 0) }
    }

    /// Carries on from the step that stopped; the loader picks up a write where it was interrupted.
    func resume() {
        guard let index = job?.index, job?.isRunning == false else { return }
        job?.phase = .preparing
        job?.needsAStepFirst = false
        job?.mightBeRefused = false
        Task { await run(from: index) }
    }

    func dismissFlash() {
        guard !isFlashing else { return }
        job = nil
        Task { await scan() }
    }

    private func run(from startIndex: Int) async {
        guard let steps = job?.steps else { return }
        var options = InstallOptions(
            confirmsSwitchingFirmware: job?.confirmsSwitchingFirmware ?? false,
            confirmsSameIdentity: job?.confirmsSameIdentity ?? false
        )
        options.confirmsReinstallingOfficial = job?.confirmsReinstallingOfficial ?? false
        setKeepAwake(true)
        defer { setKeepAwake(false) }

        for index in startIndex..<steps.count {
            job?.index = index
            job?.phase = .preparing
            job?.writtenFraction = 0
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
                let before = await updater.identify()
                let isLoaderRunning = before?.isLoader ?? false
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

                let installed = try await confirmed(result, of: package, reinstalling: before == package.identity)
                identity = installed
                record(item, from: package)
            } catch {
                if let written = job?.writtenFraction, written > 0 {
                    appendLog("Written: \(Int(written * 100))% of it.")
                }
                appendLog("✕ \(error.localizedDescription)")
                let needsAStepFirst = FlashJob.needsAStepFirst(
                    after: error, installing: item, from: job?.guide, startUp: settings?.startUp)
                let running = identity.flatMap { history.lastInstall(matching: $0.text)?.name }
                let message = FlashJob.failureMessage(
                    for: error, installing: item, running: running, needsAStepFirst: needsAStepFirst)
                job?.phase = .failed(message, canResume: FlashJob.canResume(after: error))
                job?.needsAStepFirst = needsAStepFirst
                job?.mightBeRefused = FlashJob.mightBeRefused(after: error)
                return
            }
        }
        job?.phase = .succeeded(identity?.text ?? "")
        appendLog("✓ Finished.")
    }

    /// What `result` installed, or after an error that can hide a finished install, the package's
    /// identity if the FM-1 turns out to be running it.
    private func confirmed(
        _ result: Result<FM1Identity, any Error>,
        of package: FwscPackage,
        reinstalling: Bool
    ) async throws -> FM1Identity {
        do {
            return try result.get()
        } catch {
            let written = job?.writtenFraction ?? 0
            guard FlashJob.mightHaveFinished(after: error, written: written, reinstalling: reinstalling),
                let returned = await returned(running: package)
            else {
                throw error
            }
            return returned
        }
    }

    /// Looks for the FM-1 for a while, in case it restarted into `package` without FM1Kit seeing
    /// it: its loader can restart without saying it's finished, or the FM-1 can come back where
    /// FM1Kit isn't looking.
    ///
    /// - Returns: The package's identity once the FM-1 reports it, or `nil` if it reports anything
    ///   else, or nothing in time.
    private func returned(running package: FwscPackage) async -> FM1Identity? {
        job?.phase = .rebooting
        appendLog("Looking for the FM-1, in case it restarted into the new firmware.")
        let deadline = ContinuousClock.now + FlashJob.returnSearch
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let found = await updater.identify() {
                appendLog("Device reports \(found.text).")
                return found == package.identity ? found : nil
            }
            try? await Task.sleep(for: .seconds(2))
        }
        appendLog("No FM-1 answered.")
        return nil
    }

    /// Records an install, with the guide to switching away from it, and what starts the FM-1
    /// once the install has brought a bootloader of its own.
    private func record(_ item: StoredFirmware, from package: FwscPackage) {
        let installed = SwitchingGuide.installing(
            package, named: item.name, over: job?.guide, startUp: settings?.startUp)
        history.record(item, guide: installed.guide)
        if let startUp = installed.startUp { settings?.startUp = startUp }
        job?.guide = installed.guide ?? job?.guide
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
            let written = job?.writtenFraction ?? 0
            job?.writtenFraction = max(written, fraction)
        case .checking(let fraction, _):
            if case .secondPass = job?.phase {} else { appendLog("Written once; the loader is going over it again.") }
            job?.phase = .secondPass(fraction: fraction)
            job?.writtenFraction = 1
        case .rebooting:
            job?.phase = .rebooting
            appendLog("Rebooting into the new firmware.")
        case .finished(let identity):
            appendLog("Device reports \(identity.text).")
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        logFile?.append(line)
    }

    // MARK: - Staying alive.

    /// Keeps the device awake for the whole flash, restore or backup, so the person only has to
    /// stay in the app.
    func setKeepAwake(_ on: Bool) {
        wakeKeeper.isHolding = on
    }

    /// Passes on scene changes, so a write that's under way can ask for time to finish.
    func scenePhaseChanged(to phase: ScenePhase) {
        wakeKeeper.scenePhaseChanged(to: phase, isWriting: isWriting)
    }
}
