import FM1Kit
import Foundation

/// Restoring V15's factory voices, reaching download mode and backing up open firmware.
extension DeviceController {
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
        /// Nothing is written: switching the FM-1 off and on starts its firmware again.
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
}
