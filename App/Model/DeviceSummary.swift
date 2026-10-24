import FM1Kit
import Foundation

/// The FM-1 in plain words: whether it's there, and what it's running as far as anyone can tell.
///
/// The identity alone can be ambiguous (several firmwares report `FM-1_900`), so this uses what
/// this app last installed, then the firmware list, before falling back on the identity itself.
struct DeviceSummary: Equatable {
    enum State: Equatable {
        case notConnected
        /// Running a firmware, named if it's known.
        case running(name: String?)
        /// Waiting in its update loader, part-way through an install.
        case waiting(FM1Identity)
    }

    var state: State
    /// What the FM-1 reports, such as `FM-1_916`.
    var identity: String?

    @MainActor
    init(model: AppModel) {
        guard let identity = model.device.identity else {
            self.init(state: .notConnected, identity: nil)
            return
        }
        if identity.isLoader {
            self.init(state: .waiting(identity), identity: identity.text)
            return
        }
        let matches = model.catalogue.entries(matching: identity.text)
        let name: String? =
            if let last = model.history.lastInstall(matching: identity.text) {
                "\(last.name) \(last.version)"
            } else if identity == .officialV15 {
                "the official firmware (V15)"
            } else if matches.count == 1, let match = matches.first {
                [match.name, match.version].compactMap(\.self).joined(separator: " ")
            } else {
                nil
            }
        self.init(state: .running(name: name), identity: identity.text)
    }

    init(state: State, identity: String?) {
        self.state = state
        self.identity = identity
    }

    /// The pill under the drawing.
    var statusLine: String {
        switch state {
        case .notConnected: "Not connected"
        case .running(let name?): "Connected, running \(name)"
        case .running(nil): "Connected, reporting \(identity ?? "")"
        case .waiting: "Connected, waiting to finish an install"
        }
    }

    /// The drawing's screen: the firmware's name, short enough to fit.
    var screenTitle: String {
        switch state {
        case .notConnected: "HELLO"
        case .running(let name?): name.replacingOccurrences(of: "the official firmware (V15)", with: "V15").uppercased()
        case .running(nil): identity ?? ""
        case .waiting: "UPDATE"
        }
    }

    var screenLine: String {
        switch state {
        case .notConnected: "Plug me in"
        case .running: "Ready"
        case .waiting: "Waiting…"
        }
    }
}
