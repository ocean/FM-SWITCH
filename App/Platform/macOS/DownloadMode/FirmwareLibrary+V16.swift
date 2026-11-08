import FM1Kit
import Foundation

extension FirmwareLibrary {
    /// Why V16 couldn't be had for a rescue.
    struct V16Unavailable: LocalizedError {
        var errorDescription: String? {
            """
            Couldn't get V16 from M-VAVE, or the file there isn't the V16 FM-SWITCH knows. Download \
            FM-1.fwsc from m-vave.com/download, then try again: FM-SWITCH finds it in Downloads.
            """
        }
    }

    /// M-VAVE's own link to FM-1.fwsc, for when their downloads page can't be read.
    private static let mvavePackageURL = URL(
        literal: "https://yms-file-store.oss-cn-hongkong.aliyuncs.com/software/firmware/FM-1.fwsc")

    /// The saved V16, if there is one.
    var v16: StoredFirmware? {
        items.first { $0.source == .official && $0.sha256 == OfficialFirmware.v16.sha256 }
    }

    /// Saves M-VAVE's V16 for a rescue: a copy in Downloads, found by its hash, or otherwise
    /// downloaded from M-VAVE.
    ///
    /// Only a file with V16's hash is taken, so it never installs anything unchecked.
    @discardableResult
    func getV16() async throws -> StoredFirmware {
        if let saved = v16 { return saved }
        if let found = Self.v16InDownloads() { return try importFile(at: found) }
        if let saved = try? await downloadOfficialFromMVAVE(), saved.sha256 == OfficialFirmware.v16.sha256 {
            return saved
        }
        if let saved = try? await importOfficial(from: Self.mvavePackageURL),
            saved.sha256 == OfficialFirmware.v16.sha256
        {
            return saved
        }
        throw V16Unavailable()
    }

    /// A `.fwsc` in Downloads that's V16, whatever it's called.
    private static func v16InDownloads() -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            let files = try? FileManager.default.contentsOfDirectory(
                at: downloads, includingPropertiesForKeys: [.fileSizeKey])
        else {
            return nil
        }
        return files.first { file in
            guard file.pathExtension.lowercased() == "fwsc",
                (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == OfficialFirmware.v16.size,
                let data = try? Data(contentsOf: file),
                let package = try? FwscPackage(data: data)
            else {
                return false
            }
            return OfficialFirmware.matching(package) == .v16
        }
    }
}
