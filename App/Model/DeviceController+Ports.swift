import FM1Kit

/// The MIDI ports FM-SWITCH talks to, and the ones the person chose to try, for firmwares that
/// rename their USB port.
extension DeviceController {
    /// Whether FM-SWITCH talks to a port: one named like an FM-1's, or one the person chose to try.
    func asks(_ port: MIDIPortDescriptor) -> Bool {
        updater.probes(port)
    }

    /// Whether the person chose to try a port that isn't named like an FM-1's.
    func isTried(_ port: MIDIPortDescriptor) -> Bool {
        !FM1Updater.isProbeable(port) && asks(port)
    }

    /// Talks to a port that isn't named like an FM-1's from now on, and looks for the FM-1 on it.
    ///
    /// Only the handshake query is sent, which nothing but an FM-1 answers.
    func tryPort(_ port: MIDIPortDescriptor) async {
        guard !isWriting, let settings else { return }
        settings.triedPortNames.insert(port.name)
        await scanAgain()
    }

    /// Stops talking to a port the person chose to try.
    func stopTrying(_ port: MIDIPortDescriptor) async {
        guard !isWriting, let settings else { return }
        let names = Set([port.name, port.usbProductName].compactMap { $0?.lowercased() })
        settings.triedPortNames = settings.triedPortNames.filter { !names.contains($0.lowercased()) }
        await scanAgain()
    }

    /// Scans with the ports chosen now, after any scan already under way, which may have used the
    /// earlier ones.
    private func scanAgain() async {
        while isScanning, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await scan()
    }
}
