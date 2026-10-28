import Foundation
import Security

/// Starts the flash tool as root, after the person gives their administrator password.
///
/// It uses `AuthorizationExecuteWithPrivileges`, as M-Flasher does, rather than AppleScript's
/// `with administrator privileges`: the tool then runs inside the person's login, with FM-SWITCH
/// responsible for it, so macOS can ask them to let FM-SWITCH use the FM-1 as a removable volume.
/// AppleScript's way runs it outside their login, where macOS refuses without asking.
enum ToolLauncher {
    /// `AuthorizationExecuteWithPrivileges`, which Swift can't call directly, as it's deprecated.
    private typealias ExecuteWithPrivileges =
        @convention(c) (
            AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

    /// Asks for the password, then starts the tool.
    ///
    /// It waits while the person types their password, so it's called off the main thread.
    ///
    /// - Returns: The pipe to the tool, which quits once it's closed.
    /// - Throws: ``FlashFailure`` when the person cancels or the tool can't be started.
    static func start() throws -> FlashLine {
        guard
            let tool = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: FlashTool.executableName),
            let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges")
        else { throw FlashFailure(.toolUnavailable, ToolFlashService.didntStart) }
        let execute = unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)
        var created: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &created) == errAuthorizationSuccess, let authorisation = created else {
            throw FlashFailure(.toolUnavailable, ToolFlashService.didntStart)
        }
        defer { AuthorizationFree(authorisation, []) }
        try check(askForRights(authorisation))
        var pipe: UnsafeMutablePointer<FILE>?
        let arguments: [UnsafeMutablePointer<CChar>?] = [nil]
        let status = tool.path(percentEncoded: false).withCString { toolPath in
            arguments.withUnsafeBufferPointer { buffer in
                guard let start = buffer.baseAddress else { return errAuthorizationInternal }
                return execute(authorisation, toolPath, [], start, &pipe)
            }
        }
        try check(status)
        guard let pipe else { throw FlashFailure(.toolUnavailable, ToolFlashService.didntStart) }
        // The line keeps its own descriptor, so the stream can go.
        let descriptor = dup(fileno(pipe))
        fclose(pipe)
        guard descriptor >= 0 else { throw FlashFailure(.toolUnavailable, ToolFlashService.didntStart) }
        return FlashLine(descriptor: descriptor)
    }

    /// Asks the person for the right to run a tool as root, with ``ToolFlashService/passwordPrompt``.
    private static func askForRights(_ authorisation: AuthorizationRef) -> OSStatus {
        kAuthorizationRightExecute.withCString { right in
            kAuthorizationEnvironmentPrompt.withCString { promptKey in
                ToolFlashService.passwordPrompt.withCString { prompt in
                    var rightItem = AuthorizationItem(name: right, valueLength: 0, value: nil, flags: 0)
                    var promptItem = AuthorizationItem(
                        name: promptKey,
                        valueLength: strlen(prompt),
                        value: UnsafeMutableRawPointer(mutating: prompt),
                        flags: 0
                    )
                    return withUnsafeMutablePointer(to: &rightItem) { rightPointer in
                        withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                            var rights = AuthorizationRights(count: 1, items: rightPointer)
                            var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                            let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                            return AuthorizationCopyRights(authorisation, &rights, &environment, flags, nil)
                        }
                    }
                }
            }
        }
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errAuthorizationSuccess: return
        case errAuthorizationCanceled: throw FlashFailure(.toolUnavailable, ToolFlashService.cancelled)
        default:
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw FlashFailure(
                .toolUnavailable, "FM-SWITCH's flash tool didn't start (\(reason)). Nothing was written.")
        }
    }
}
