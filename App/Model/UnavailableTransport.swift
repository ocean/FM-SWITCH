import FM1Kit

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
