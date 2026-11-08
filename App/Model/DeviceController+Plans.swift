import FM1Kit

/// What the FM-1 is running as far as switching away goes, which device is worked with, and what
/// an install will put on it.
extension DeviceController {
    /// The simulated FM-1 being worked with: the one chosen, when there are two.
    var simulatedDevice: SimulatedFM1? {
        guard let pair = transport as? SimulatedPair else { return transport as? SimulatedFM1 }
        return chosenDevice.map { pair.device(on: $0.port) }
    }

    /// Whether more than one device is connected and none has been chosen yet.
    var needsChoice: Bool { devices.count > 1 && chosenDevice == nil }

    /// The guide to switching away from what the FM-1 is running, when that's known: from the
    /// last install from this app, or for M-VAVE's firmwares, from its identity.
    var runningGuide: LeavingGuide? {
        guard let identity else { return nil }
        let saved = history.lastInstall(matching: identity.text)?.guide
        return SwitchingGuide.running(identity, saved: saved, startUp: settings?.startUp)
    }

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

    /// Starts the stopped install again with `fixedFirmware` on first, as the firmware on the
    /// FM-1 refused what it was installing: MIDIMON or LOOM-8, which it takes, and which take
    /// anything.
    ///
    /// Only for an install the person confirmed switching firmware for, as this switches too.
    func installFirst(_ fixedFirmware: StoredFirmware) {
        guard let job, !job.isRunning, job.confirmsSwitchingFirmware else { return }
        flash(
            [fixedFirmware] + job.steps[job.index...],
            confirmsSwitchingFirmware: true,
            confirmsReinstallingOfficial: job.confirmsReinstallingOfficial,
            startedOnV16: job.startedOnV16
        )
    }
}
