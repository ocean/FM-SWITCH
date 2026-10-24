import CoreTransferable
import FM1Kit
import Foundation
import Observation
import UniformTypeIdentifiers

/// One saved copy of an FM-1's projects and samples: a folder of the files M-VAVE's workbench
/// reads, with FM1Kit's `backup.json` describing them.
struct SavedBackup: Identifiable, Hashable, Sendable {
    var folder: URL
    var date: Date
    /// What the FM-1 reported, such as `FM-1_8000012`.
    var identity: String
    /// The saved slots' project names, in slot order.
    var projectNames: [String]
    /// The sample bank's size, or nil when there was none.
    var sampleBytes: Int?

    var id: URL { folder }

    /// What was saved, in a few words: "5 projects and your samples".
    var contentsLine: String {
        let projects = projectNames.count == 1 ? "1 project" : "\(projectNames.count) projects"
        guard let sampleBytes else { return "\(projects) and the project you were working on" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(sampleBytes), countStyle: .file)
        return "\(projects), the project you were working on, and your samples (\(size))"
    }
}

/// The saved copies of FM-1s, newest first, in a Backups folder: in iCloud Drive when it's on (see
/// ``SharedStorage``), otherwise in Documents on this device.
@MainActor
@Observable
final class BackupStore {
    private(set) var backups: [SavedBackup] = []
    private(set) var directory: URL

    init(directory: URL = SharedStorage.onDevice.backups) {
        self.directory = directory
        reload()
    }

    /// Reads the backups from disk again, as another device may have added some.
    ///
    /// Backups whose files haven't arrived from iCloud Drive yet start downloading, and are left out
    /// until their `backup.json` has.
    func reload() {
        let folders = SharedStorage.contents(of: directory).filter { !$0.lastPathComponent.hasPrefix(".") }
        for folder in folders {
            _ = SharedStorage.contents(of: folder)
        }
        backups = folders.compactMap(Self.read).sorted { $0.date > $1.date }
    }

    /// Moves every backup into `newDirectory` and saves there from now on: into iCloud Drive, once
    /// it's known to be on.
    func move(to newDirectory: URL) async {
        guard newDirectory.standardizedFileURL != directory.standardizedFileURL else { return }
        await SharedStorage.move(directory, into: newDirectory)
        directory = newDirectory
        reload()
    }

    /// Writes a backup into a folder of its own, named after the date it was made.
    ///
    /// - Returns: The saved backup.
    /// - Throws: Any error writing its files.
    func save(_ backup: OpenFirmwareBackup) throws -> SavedBackup {
        let folder = freeFolder(for: backup.date)
        try backup.write(to: folder)
        reload()
        guard let saved = backups.first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: folder.path])
        }
        return saved
    }

    func delete(_ backup: SavedBackup) throws {
        try FileManager.default.removeItem(at: backup.folder)
        reload()
    }

    /// "FM-1 2026-10-23 at 13.45", with a number after it if that's taken.
    private func freeFolder(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        let name = "FM-1 \(formatter.string(from: date))"
        var folder = directory.appending(path: name, directoryHint: .isDirectory)
        var number = 2
        while SharedStorage.exists(folder) {
            folder = directory.appending(path: "\(name) (\(number))", directoryHint: .isDirectory)
            number += 1
        }
        return folder
    }

    /// The backup in `folder`, from its `backup.json`, or nil if it has none.
    private static func read(_ folder: URL) -> SavedBackup? {
        guard let data = try? Data(contentsOf: folder.appending(path: "backup.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return nil }
        return SavedBackup(
            folder: folder,
            date: manifest.date,
            identity: manifest.identity,
            projectNames: manifest.slots.compactMap { $0.file == nil ? nil : $0.name ?? "Slot \($0.slot)" },
            sampleBytes: manifest.samples == nil ? nil : manifest.sampleBytes)
    }
}

/// The parts of FM1Kit's `backup.json` that ``BackupStore`` shows.
private struct Manifest: Decodable {
    var identity: String
    var date: Date
    var slots: [ManifestSlot]
    var samples: String?
    var sampleBytes: Int?
}

/// A slot in `backup.json`: its number from 1, and its name and file unless it's empty.
private struct ManifestSlot: Decodable {
    var slot: Int
    var name: String?
    var file: String?
}

/// A backup as one zip file, for sharing: made when it's shared.
struct BackupArchive: Transferable {
    var backup: SavedBackup

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            SentTransferredFile(try archive.zipped())
        }
    }

    /// Zips the backup's folder into a temporary file, as Files does when a folder is shared.
    nonisolated func zipped() throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: backup.folder.lastPathComponent + ".zip")
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(
            readingItemAt: backup.folder, options: .forUploading, error: &coordinationError
        ) { zip in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zip, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }
}
