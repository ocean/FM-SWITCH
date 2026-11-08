import FM1Kit

/// Two simulated FM-1s on one connection, for trying the choice between them without two real ones.
///
/// Each port's identifier starts with which one it is, `1-` or `2-`.
final class SimulatedPair: MIDITransport, Sendable {
    let first: SimulatedFM1
    let second: SimulatedFM1

    init(_ first: SimulatedFM1, _ second: SimulatedFM1) {
        self.first = first
        self.second = second
    }

    /// The simulated FM-1 the settings describe, or two, when they ask for a second running V15.
    @MainActor
    static func transport(for settings: AppSettings) -> any MIDITransport {
        var options = SimulatedFM1.Options()
        options.startsInRecoveryMode = settings.simulatedRecoveryMode
        options.unplugDuringWriteAt = settings.simulatedCablePull ? 0.45 : nil
        options.writesBackwards = settings.simulatedReadsBackwards
        options.checksAfterWriting = settings.simulatedVerifies
        if settings.simulatedMBootloader {
            options.bootloaderVersion = "2.1"
            options.comparesBootArea = true
        }
        if settings.simulatedOpenFirmware { SimulatedOpenFirmware.apply(to: &options) }
        guard settings.simulatedSecondFM1 else { return SimulatedFM1(options: options) }
        var v15 = SimulatedFM1.Options()
        v15.installedIdentity = .officialV15
        return SimulatedPair(SimulatedFM1(options: options), SimulatedFM1(options: v15))
    }

    /// The one listed on `port`.
    func device(on port: MIDIPortDescriptor) -> SimulatedFM1 {
        port.id.hasPrefix("2-") ? second : first
    }

    func ports() async -> [MIDIPortDescriptor] {
        let one = await first.ports().map { Self.port($0, prefix: "1-") }
        let two = await second.ports().map { Self.port($0, prefix: "2-") }
        return one + two
    }

    func open(_ port: MIDIPortDescriptor) async throws -> any MIDIConnection {
        try await device(on: port).open(
            MIDIPortDescriptor(id: String(port.id.dropFirst(2)), name: port.name, serialNumber: port.serialNumber))
    }

    func changes() -> AsyncStream<Void> {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let watches = [first, second].map { device in
            Task {
                for await _ in device.changes() {
                    continuation.yield()
                }
            }
        }
        continuation.onTermination = { _ in
            for watch in watches {
                watch.cancel()
            }
        }
        return changes
    }

    /// The port as this lists it, its identifier prefixed with which device it's on.
    private static func port(_ port: MIDIPortDescriptor, prefix: String) -> MIDIPortDescriptor {
        MIDIPortDescriptor(id: prefix + port.id, name: port.name, serialNumber: port.serialNumber)
    }
}
