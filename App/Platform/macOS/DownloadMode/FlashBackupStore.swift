import Foundation
import Observation

/// One whole-flash backup: a 1 MB `.bin` and its `.json`, as FM1Kit and M-Flasher save them.
struct SavedFlashBackup: Identifiable, Hashable, Sendable {
    /// The `.bin` file.
    var file: URL
    var date: Date
    /// The firmware on it, such as "V15 (FM-1_015)", if its `.json` says.
    var firmware: String?
    /// The bootloader on it, such as "m-bootloader 1.2-22e2559", if its `.json` says.
    var bootloader: String?

    var id: URL { file }

    /// The name the person gave it, or `nil` while it has the name it was saved with.
    var name: String? {
        let base = file.deletingPathExtension().lastPathComponent
        return base.wholeMatch(of: /fm1-\d{8}-\d{6}/) == nil ? base : nil
    }

    /// Its name, or when it was made.
    var title: String { name ?? date.formatted(date: .abbreviated, time: .shortened) }

    /// What's on it, and when it was made if its title doesn't say.
    var detailLine: String {
        guard name != nil else { return contentsLine }
        return "\(date.formatted(date: .abbreviated, time: .shortened)) · \(contentsLine)"
    }

    /// The firmware and bootloader, in a few words.
    var contentsLine: String {
        let parts = [firmware.map { "Firmware: \($0)" }, bootloader.map { "bootloader: \($0)" }].compactMap(\.self)
        return parts.isEmpty ? file.lastPathComponent : parts.joined(separator: ", ")
    }
}

/// Whole-flash backups, newest first, in Backups › Whole flash: in iCloud Drive with the rest
/// when it's on.
@MainActor
@Observable
final class FlashBackupStore {
    private(set) var backups: [SavedFlashBackup] = []
    private let backupsFolder: @MainActor () -> URL

    /// - Parameter backupsFolder: The Backups folder, which moves into iCloud Drive once it's on.
    init(backupsFolder: @escaping @MainActor () -> URL) {
        self.backupsFolder = backupsFolder
        reload()
    }

    var directory: URL { backupsFolder().appending(path: "Whole flash", directoryHint: .isDirectory) }

    func reload() {
        backups = SharedStorage.contents(of: directory)
            .filter { $0.pathExtension.lowercased() == "bin" }
            .map(Self.read)
            .sorted { $0.date > $1.date }
    }

    /// Saves `files` beside the other backups, never replacing one, unless a backup already
    /// holds the same flash.
    ///
    /// - Returns: The saved backup, or the one that already holds the same flash.
    /// - Throws: Any error writing its files.
    func save(_ files: FlashFiles) throws -> SavedFlashBackup {
        // Backups still only in iCloud Drive can't be read here, so they're never matched.
        if let same = backups.first(where: { (try? Data(contentsOf: $0.file)) == files.flash }) { return same }
        let file = try files.write(to: directory)
        reload()
        return backups.first { $0.file.standardizedFileURL == file.standardizedFileURL } ?? Self.read(file)
    }

    /// The backup's files, fetched from iCloud Drive first if they're still on their way.
    func files(of backup: SavedFlashBackup) async throws -> FlashFiles {
        try await SharedStorage.download(backup.file)
        let description = backup.file.deletingPathExtension().appendingPathExtension("json")
        if SharedStorage.exists(description) { try await SharedStorage.download(description) }
        return try FlashFiles(contentsOf: backup.file)
    }

    /// Renames the backup's `.bin` and `.json`, fetching them from iCloud Drive first if they're
    /// still on their way, or gives them back the name they were saved with when `name` is blank.
    ///
    /// - Returns: The renamed backup.
    /// - Throws: Any error fetching or moving its files, as when another backup has the name.
    func rename(_ backup: SavedFlashBackup, to name: String) async throws -> SavedFlashBackup {
        let cleaned = name.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines.union(["."]))
        let base = cleaned.isEmpty ? "fm1-\(Self.savedFormat.string(from: backup.date))" : cleaned
        let file = directory.appending(path: base).appendingPathExtension("bin")
        guard file.standardizedFileURL != backup.file.standardizedFileURL else { return backup }
        let description = backup.file.deletingPathExtension().appendingPathExtension("json")
        try await SharedStorage.download(backup.file)
        let hasDescription = SharedStorage.exists(description)
        if hasDescription { try await SharedStorage.download(description) }
        try FileManager.default.moveItem(at: backup.file, to: file)
        if hasDescription {
            try FileManager.default.moveItem(
                at: description, to: file.deletingPathExtension().appendingPathExtension("json"))
        }
        reload()
        return backups.first { $0.file.standardizedFileURL == file.standardizedFileURL } ?? Self.read(file)
    }

    func delete(_ backup: SavedFlashBackup) throws {
        try FileManager.default.removeItem(at: backup.file)
        try? FileManager.default.removeItem(at: backup.file.deletingPathExtension().appendingPathExtension("json"))
        reload()
    }

    /// Reads what the `.json` beside `file` says about it, as M-Flasher writes it.
    private static func read(_ file: URL) -> SavedFlashBackup {
        let description = file.deletingPathExtension().appendingPathExtension("json")
        let fields =
            (try? Data(contentsOf: description))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let saved = (fields["saved"] as? String).flatMap(savedFormat.date)
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return SavedFlashBackup(
            file: file,
            date: saved ?? modified ?? .distantPast,
            firmware: fields["firmware"] as? String,
            bootloader: fields["bootloader"] as? String)
    }

    /// The `.json`'s "saved" stamp, such as `20261025-161200`.
    private static let savedFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
