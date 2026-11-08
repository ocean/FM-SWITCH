import Foundation

/// An install's log, saved line by line as it goes, so what happened can still be read once the
/// app has moved on or quit.
///
/// On the Mac they're in ~/Library/Logs/FM-SWITCH, where Console shows them too; on iPhone and iPad,
/// in the app's own Library. Only the newest few are kept.
struct InstallLogFile {
    static let folder = URL.libraryDirectory.appending(path: "Logs/FM-SWITCH", directoryHint: .isDirectory)
    static let kept = 20

    let url: URL
    private let started = ContinuousClock.now

    /// Names that sort in the order the installs started.
    private static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// Starts a log in `folder`, named for when it started, and clears out the oldest.
    ///
    /// - Returns: `nil` if the folder can't be made, in which case nothing is saved.
    init?(in folder: URL = Self.folder, date: Date = .now) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        url = folder.appending(path: "Install \(Self.fileDate.string(from: date)).log")
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else { return nil }
        Self.prune(folder)
        append(Self.heading(date))
    }

    /// Adds `line`, with how long after the start it came.
    func append(_ line: String) {
        let elapsed = (ContinuousClock.now - started).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let data = Data("+\(seconds.formatted(.number.precision(.fractionLength(1)))) s  \(line)\n".utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// The app's version and the system it's on, to start the log.
    private static func heading(_ date: Date) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        return "FM-SWITCH \(version) (\(build)), \(system), \(date.formatted(.iso8601))"
    }

    /// Deletes all but the newest ``kept`` logs.
    private static func prune(_ folder: URL) {
        let logs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let oldest = logs.filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(kept)
        for log in oldest {
            try? FileManager.default.removeItem(at: log)
        }
    }
}
