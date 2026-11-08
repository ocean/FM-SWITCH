import FM1Kit

/// The words for choosing one of several connected devices, which both looks show.
enum DeviceChoice {
    static let title = "Which FM-1?"
    static let detail = "More than one is connected. Choose the one to work with: the others are left alone."
    static let chooseFirst = "More than one FM-1 is connected. Choose one on My FM-1 first."

    /// What a device is running, for its row: the firmware's name when it's known.
    @MainActor
    static func name(of device: FM1DeviceSummary, in model: AppModel) -> String {
        if device.isWaitingMidUpdate { return "Waiting to finish an install" }
        if let name = device.firmwareName { return "Running \(name)" }
        let matches = model.catalogue.entries(matching: device.identity.text)
        if matches.count == 1, let match = matches.first { return "Running \(match.name)" }
        return "Reporting \(device.identity.text)"
    }

    /// Which port it's on, and its serial number when it has one, to tell two the same apart.
    static func detail(of device: FM1DeviceSummary) -> String {
        ["On \(device.portName)", device.serialNumber.map { "serial number \($0)" }]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    /// The device in `found` that's `device`, which comes back on a new port after restarting:
    /// on the same port, or with the same serial number, or the only one reporting `identity`.
    static func same(_ device: FM1DeviceSummary, in found: [FM1DeviceSummary], identity: FM1Identity?)
        -> FM1DeviceSummary?
    {
        if let samePort = found.first(where: { $0.id == device.id }) { return samePort }
        if let serial = device.serialNumber, let sameSerial = found.first(where: { $0.serialNumber == serial }) {
            return sameSerial
        }
        let reporting = found.filter { $0.identity == identity }
        return reporting.count == 1 ? reporting.first : nil
    }
}
