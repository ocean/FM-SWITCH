import Foundation
import Security

/// The Mac's privileged helper, which reads and writes an FM-1's flash in the chip's download
/// mode: taking the FM-1 from macOS's disk driver needs root.
///
/// The app registers it with `SMAppService` from its launchd property list, and talks to it over
/// XPC. Each side checks the other is signed by the same team: the helper only answers
/// FM-SWITCH, and FM-SWITCH only talks to its own helper.
enum FlashHelper {
    /// The helper's launchd label and XPC service name.
    static let serviceName = "dev.drewr.fmswitch.helper"
    /// Its launchd property list, in the app's Contents/Library/LaunchDaemons.
    static let plistName = "dev.drewr.fmswitch.helper.plist"
    /// The app's bundle identifier, which the helper answers.
    static let appIdentifier = "dev.drewr.fmswitch"

    /// The code-signing requirement for `identifier`, signed by the same team as this process.
    ///
    /// - Returns: The requirement, or `nil` when this process isn't signed by a team, when
    ///   neither side could be checked.
    static func requirement(forIdentifier identifier: String) -> String? {
        guard let team = teamIdentifier() else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The team that signed this process, or `nil` when it isn't signed by one.
    private static func teamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let fields = information as? [String: Any]
        else { return nil }
        return fields[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// What the app asks the helper.
///
/// Each reply carries JSON: a result, or a ``FlashFailure``. The helper keeps one FM-1 open
/// between calls, so a write is planned against the flash it has just read.
@objc protocol FlashHelperProtocol {
    /// Reads the whole flash, twice, checked against the chip's CRC-32: a ``FlashReading``.
    func readFlash(reply: @escaping @Sendable (Data?, Data?) -> Void)
    /// Plans a ``FlashRequest`` against the flash last read: a ``FlashPlanSummary``.
    func plan(_ request: Data, reply: @escaping @Sendable (Data?, Data?) -> Void)
    /// Writes the plan last made and checks it: a failure, or nil.
    func write(reply: @escaping @Sendable (Data?) -> Void)
    /// Lets go of the FM-1, which stays in download mode until it's switched off and on.
    func close(reply: @escaping @Sendable () -> Void)
}

/// What the helper tells the app while it reads or writes.
@objc protocol FlashProgressProtocol {
    /// How far it's got, from 0 to 1.
    func progress(_ fraction: Double)
}
