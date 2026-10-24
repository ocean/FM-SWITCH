import Foundation

extension FirmwareLibrary {
    enum Failure: LocalizedError {
        case download(String)
        case noPackage
        case hashMismatch
        case productMismatch(expected: String, found: String)
        case notOfficial
        case officialNotFound

        var errorDescription: String? {
            switch self {
            case .download(let reason):
                return "Download failed: \(reason)"
            case .noPackage:
                return "No downloadable file is known for this firmware. Get it from the project's own links."
            case .hashMismatch:
                return """
                    The downloaded file doesn't match its published size or checksum, so it was not saved. \
                    Refresh the list and try again.
                    """
            case .productMismatch(let expected, let found):
                return "The file reports \(found), but the catalogue says \(expected). Not saved."
            case .notOfficial:
                return """
                    That file isn't a recognised official FM-1 firmware \
                    (only an unmodified V15 FM-1.fwsc is accepted).
                    """
            case .officialNotFound:
                return """
                    Couldn't find FM-1.fwsc on M-VAVE's downloads page. \
                    Download it in Safari and import it from Files.
                    """
            }
        }
    }
}
