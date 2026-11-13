import Foundation

/// The credit The Firmware Hub's terms ask for wherever its list is used or passed on: the hub
/// named with its address, the licence, and what was changed (thefirmwarehub.com/kb/, "Using the
/// hub's firmware list").
enum ListCredit {
    /// The hub, named as its terms ask.
    static let hub = "Firmware list: The Firmware Hub – thefirmwarehub.com"
    static let hubURL = URL(literal: "https://thefirmwarehub.com")
    static let licence = "CC BY 4.0"
    static let licenceURL = URL(literal: "https://creativecommons.org/licenses/by/4.0/")
    /// What FM-SWITCH changes, and whose the firmwares' words and pictures are.
    static let changes = """
        FM-SWITCH changes it: it adds the firmwares on fm1-editor.com, aroum's FM1 Resource Hub and \
        mutant.cloud, and downloads each firmware from its maker, not from the hub. Each firmware's \
        words and pictures are its maker's; its page names them and links its project.
        """

    /// All of it in one line, for the published list, where links don't work.
    static let plain = "\(hub) (\(hubURL.absoluteString)), under \(licence) (\(licenceURL.absoluteString)). \(changes)"
}
