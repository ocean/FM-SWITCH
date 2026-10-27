import Foundation
import Observation

/// The firmwares the person has starred to come back to, whether or not they've saved them.
///
/// They're kept as Starred.json beside the Firmwares and Backups folders, so with iCloud Drive on,
/// the person's other devices have the same stars.
@MainActor
@Observable
final class StarredFirmwares {
    /// The starred firmwares' catalogue IDs.
    private(set) var ids: Set<String> = []
    private var folder: URL

    init(folder: URL = SharedStorage.onDevice.root) {
        self.folder = folder
        reload()
    }

    private var file: URL { folder.appending(path: Self.fileName) }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.remove(id) == nil { ids.insert(id) }
        save()
    }

    /// Reads the stars again, after another device has changed them.
    ///
    /// A file still on its way from iCloud Drive leaves the stars as they are until it arrives.
    func reload() {
        guard SharedStorage.exists(file) else {
            ids = []
            return
        }
        guard let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            return
        }
        ids = Set(stored.starred)
    }

    /// Moves the stars into `newFolder`, joining them with any another device has left there.
    func move(to newFolder: URL) async {
        guard newFolder != folder else { return }
        let old = file
        let mine = ids
        folder = newFolder
        if SharedStorage.exists(file) { try? await SharedStorage.download(file) }
        reload()
        ids.formUnion(mine)
        save()
        try? FileManager.default.removeItem(at: old)
    }

    private func save() {
        let stored = Stored(starred: ids.sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static let fileName = "Starred.json"

    /// What's in the file.
    private struct Stored: Codable {
        var starred: [String]
    }
}
