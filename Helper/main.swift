// FM-SWITCH's privileged helper: reads and writes an FM-1's flash in the chip's download mode,
// for the app, over XPC.
//
// launchd starts it as root when the app connects, from the property list SMAppService
// registered. It answers only FM-SWITCH signed by the same team, and quits once it's been idle
// for a minute.

import Foundation

/// How long the helper waits with no app connected before quitting.
let idleLimit: TimeInterval = 60

guard let requirement = FlashHelper.requirement(forIdentifier: FlashHelper.appIdentifier) else {
    // Unsigned, so it couldn't tell FM-SWITCH from anything else.
    FileHandle.standardError.write(Data("FMSwitchHelper isn't signed by a team, so it won't answer.\n".utf8))
    exit(1)
}

let delegate = HelperListener()
let listener = NSXPCListener(machServiceName: FlashHelper.serviceName)
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = delegate
listener.resume()
delegate.quitIfIdle()
dispatchMain()
