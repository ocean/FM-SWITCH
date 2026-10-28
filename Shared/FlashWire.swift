import FM1Kit
import FM1Rescue
import Foundation

/// A whole-flash backup's two files, as FM1Kit and M-Flasher save them: a 1 MB `.bin` and the
/// `.json` describing it.
///
/// It's how backups travel between the flash tool and the app, which saves them.
struct FlashFiles: Codable, Sendable, Hashable {
    /// The `.bin` file's name, such as `fm1-20261025-161200.bin`.
    var name: String
    var flash: Data
    var description: Data

    /// The files `backup` saves as.
    ///
    /// - Throws: Any error writing them to a temporary folder or reading them back.
    init(_ backup: FlashBackup) throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try backup.write(to: folder)
        name = files.flash.lastPathComponent
        flash = try Data(contentsOf: files.flash)
        description = try Data(contentsOf: files.description)
    }

    /// Reads `url`, a `.bin`, and the `.json` beside it if there is one.
    ///
    /// - Throws: Any error reading the `.bin`.
    init(contentsOf url: URL) throws {
        name = url.lastPathComponent
        flash = try Data(contentsOf: url)
        description = (try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))) ?? Data()
    }

    /// The backup the files hold.
    ///
    /// - Throws: ``DownloadModeError/unexpectedFlashSize(_:)`` when the `.bin` isn't 1 MB.
    func backup() throws -> FlashBackup {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        return try FlashBackup(contentsOf: write(to: folder))
    }

    /// Saves both files into `folder`, never replacing one.
    ///
    /// - Returns: The `.bin` file.
    /// - Throws: Any error creating the folder or writing a file.
    @discardableResult
    func write(to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let flashURL = folder.appending(path: name)
        try flash.write(to: flashURL, options: .withoutOverwriting)
        if !description.isEmpty {
            try description.write(
                to: flashURL.deletingPathExtension().appendingPathExtension("json"), options: .withoutOverwriting)
        }
        return flashURL
    }

    private static func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

/// The FM-1's flash as just read: the backup, and what's on it.
struct FlashReading: Codable, Sendable, Hashable {
    var files: FlashFiles
    /// The bootloader, such as "m-bootloader 1.2-22e2559" or "M-VAVE's".
    var bootloader: String
    /// Whether it's m-bootloader, so holding REC while switching on reaches download mode.
    var hasMBootloader: Bool
    /// The firmware in words, such as "V15 (FM-1_015)".
    var firmware: String
    /// Whether the firmware's files are whole.
    var isFirmwareIntact: Bool

    init(_ backup: FlashBackup) throws {
        files = try FlashFiles(backup)
        bootloader = backup.bootloaderDescription
        hasMBootloader = backup.mBootloader != nil
        let check = backup.firmware
        firmware = check.description
        isFirmwareIntact = check.files == .intact
    }
}

/// A change to make to the FM-1's flash, planned against what's on it.
enum FlashRequest: Codable, Sendable, Hashable {
    /// Puts a whole-flash backup back.
    case restore(FlashFiles)
    /// Installs a firmware package's image, keeping the bootloader, and erasing the firmware's
    /// settings if asked.
    case firmware(Data, erasingSettings: Bool)
    /// Installs m-bootloader from its `.boot` file.
    case mBootloader(Data)
    /// Puts back the bootloader in a firmware package: M-VAVE's, from V15's.
    case packageBootloader(Data)

    /// Plans the change against `current`.
    ///
    /// - Throws: ``FlashPlanError``, ``FwscPackage/Failure`` for a damaged package, or
    ///   ``FlashFailure`` for a `.boot` file that isn't m-bootloader's.
    func plan(onto current: FlashBackup) throws -> FlashPlan {
        switch self {
        case .restore(let files):
            return try FlashPlan.restoring(files.backup(), onto: current)
        case .firmware(let data, let erasingSettings):
            return try FlashPlan.installing(FwscPackage(data: data), onto: current, erasingSettings: erasingSettings)
        case .mBootloader(let data):
            guard let bootloader = BootloaderImage(data: data) else {
                throw FlashFailure(
                    .other, "This isn't m-bootloader's .boot file, or it's damaged. Nothing was written.")
            }
            return try FlashPlan.installing(bootloader, onto: current)
        case .packageBootloader(let data):
            return try FlashPlan.installingBootloader(from: FwscPackage(data: data), onto: current)
        }
    }
}

/// What a planned write does, to show before asking to write it.
struct FlashPlanSummary: Codable, Sendable, Hashable {
    /// What it does, in sentences.
    var notes: [String]
    /// What to know before confirming, in sentences.
    var warnings: [String]
    /// How many 4 KB sectors change; none when the FM-1 already holds it.
    var sectorCount: Int
    /// Whether it writes the boot area, where the bootloader is.
    var writesBootArea: Bool
    /// Whether m-bootloader is on the FM-1 now, and stays.
    var keepsMBootloader: Bool

    /// The boot area at the start of the flash, as FM1Rescue defines it.
    static let bootArea = 0..<0x4000

    init(_ plan: FlashPlan) {
        notes = plan.notes
        warnings = plan.warnings
        sectorCount = plan.sectors.count
        writesBootArea = plan.sectors.contains { Self.bootArea.contains($0) }
        keepsMBootloader = !writesBootArea && plan.original.mBootloader != nil
    }

    var isEmpty: Bool { sectorCount == 0 }
}

/// Why reading or writing the flash failed, as it travels from the flash tool.
struct FlashFailure: Error, Codable, Sendable, Hashable, LocalizedError {
    /// The kinds the app treats differently.
    enum Kind: String, Codable, Sendable {
        /// No FM-1 is in download mode.
        case notFound
        /// A write stopped part-way or didn't check out, so the flash may be half-written.
        case writeFailed
        /// The flash tool didn't start, as when the password was cancelled.
        case toolUnavailable
        case other
    }

    var kind: Kind
    var message: String

    init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    /// The failure `error` amounts to.
    init(_ error: any Error) {
        switch error {
        case let failure as Self:
            self = failure
        case let error as DownloadModeError:
            switch error {
            case .notFound: self.init(.notFound, error.localizedDescription)
            case .writeNotVerified, .writeInterrupted: self.init(.writeFailed, error.localizedDescription)
            default: self.init(.other, error.localizedDescription)
            }
        default:
            self.init(.other, error.localizedDescription)
        }
    }

    var errorDescription: String? { message }
}

extension JSONEncoder {
    /// `value` as JSON, or no bytes if it can't be encoded, which the other side reads as a
    /// failure.
    static func flashMessage(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
