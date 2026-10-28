import Darwin
import Foundation

/// The Mac's flash tool, which reads and writes an FM-1's flash in the chip's download mode:
/// taking the FM-1 from macOS's disk driver needs root.
///
/// The app starts it with the person's administrator password, as a child of the app, so it runs
/// inside their login with FM-SWITCH responsible for it, and macOS can ask them to let FM-SWITCH use
/// the FM-1 as a removable volume. The two talk over the pipe macOS gives the app, which is the
/// tool's standard input and output, so nothing else can reach it.
enum FlashTool {
    /// The tool's executable, in the app's Contents/MacOS.
    static let executableName = "FMSwitchHelper"
}

/// What the app asks the tool, one step at a time.
///
/// The tool keeps one FM-1 open between steps, so a write is planned against the flash it has
/// just read.
enum FlashCommand: Codable, Sendable {
    /// Reads the whole flash, twice, checked against the chip's CRC-32.
    case read
    /// Plans a change against the flash last read.
    case plan(FlashRequest)
    /// Writes the plan last made and checks it.
    case write
    /// Lets go of the FM-1, which stays in download mode until it's switched off and on, and quits.
    case close
}

/// What the tool tells the app: progress while it works, then one answer for each step.
enum FlashEvent: Codable, Sendable {
    /// How far it's got, from 0 to 1.
    case progress(Double)
    case reading(FlashReading)
    case summary(FlashPlanSummary)
    /// A write or close is done.
    case done
    case failure(FlashFailure)
}

/// One end of the pipe between the app and the tool, carrying a JSON message a line.
///
/// It isn't safe to share between threads: each side uses it from one at a time.
final class FlashLine: @unchecked Sendable {
    /// Why the pipe stopped.
    struct Failure: Error, LocalizedError {
        var errorDescription: String?

        init(_ description: String) {
            errorDescription = description
        }

        /// A failed C call, named `name`, with the reason `errno` gives.
        static func system(_ name: String) -> Self {
            Self("\(name) failed: \(String(cString: strerror(errno)))")
        }
    }

    private let reading: Int32
    private let writing: Int32
    private let closesOnEnd: Bool
    private var buffer = Data()

    /// The app's end: one descriptor, read and written, closed when it's done with.
    init(descriptor: Int32) {
        reading = descriptor
        writing = descriptor
        closesOnEnd = true
        // A tool that's gone fails a send, rather than ending the app.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The tool's end: its standard input and output.
    static func standard() -> FlashLine {
        // An app that's gone fails a send, rather than ending the tool.
        signal(SIGPIPE, SIG_IGN)
        return FlashLine(reading: STDIN_FILENO, writing: STDOUT_FILENO)
    }

    private init(reading: Int32, writing: Int32) {
        self.reading = reading
        self.writing = writing
        closesOnEnd = false
    }

    deinit {
        if closesOnEnd { Darwin.close(reading) }
    }

    // MARK: - Messages.

    /// Sends `message` as one line of JSON.
    func send(_ message: some Encodable) throws {
        var data = try JSONEncoder().encode(message)
        data.append(UInt8(ascii: "\n"))
        try data.withUnsafeBytes { bytes in
            guard let start = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.write(writing, start + sent, bytes.count - sent)
                guard count > 0 else { throw Failure.system("write") }
                sent += count
            }
        }
    }

    /// Waits for the next message.
    ///
    /// - Throws: ``Failure`` when the other side has gone, or a decoding error.
    func receive<Message: Decodable>(_ type: Message.Type) throws -> Message {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<end]
                defer { buffer.removeSubrange(buffer.startIndex...end) }
                return try JSONDecoder().decode(type, from: line)
            }
            let count = Darwin.read(reading, &chunk, chunk.count)
            guard count > 0 else { throw count == 0 ? Failure("the other side closed") : Failure.system("read") }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
