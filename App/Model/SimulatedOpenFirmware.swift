import FM1Kit

/// The simulated FM-1's open firmware: a few saved projects and a sample bank, for trying Save my
/// FM-1 without one.
enum SimulatedOpenFirmware {
    /// What open firmware V12 reports.
    static let identity = FM1Identity(model: "FM-1", version: 8_000_012)

    static func apply(to options: inout SimulatedFM1.Options) {
        options.installedIdentity = identity
        options.projectSlots = [
            0: SimulatedFM1.ProjectSlot(name: "Night Drive", project: project(1)),
            1: SimulatedFM1.ProjectSlot(name: "Bassline", project: project(2)),
            4: SimulatedFM1.ProjectSlot(name: "Choir Pad", project: project(3)),
        ]
        options.workspace = project(4)
        options.currentSlot = 0
        options.sampleBank = (0..<48_000).map { UInt8($0 % 251) }
    }

    /// A version 4 project, different for each seed.
    static func project(_ seed: UInt8) -> OpenFirmwareProject {
        var bytes = [UInt8](repeating: 0, count: 4064)
        bytes[3852] = 4
        for index in 0..<64 { bytes[index] = seed &+ UInt8(index) }
        guard let project = OpenFirmwareProject(bytes: bytes) else {
            preconditionFailure("A 4064-byte project with version 4 is always valid.")
        }
        return project
    }
}
