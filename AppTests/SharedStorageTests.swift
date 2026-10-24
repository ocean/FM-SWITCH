import Foundation
import Testing

@testable import FMSwitch

/// Files in the shared folder, including ones still on their way from iCloud Drive.
struct SharedStorageTests {
    private static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// iCloud Drive stands `.name.icloud` in for a file until it arrives.
    @Test func listsFilesStillOnTheirWayByTheirRealNames() throws {
        let folder = try Self.folder()
        try Data().write(to: folder.appending(path: ".Felucca 1.2.fwsc.icloud"))
        try Data().write(to: folder.appending(path: "Sloop.fwsc"))
        let names = SharedStorage.contents(of: folder).map(\.lastPathComponent).sorted()
        #expect(names == ["Felucca 1.2.fwsc", "Sloop.fwsc"])
        #expect(SharedStorage.exists(folder.appending(path: "Felucca 1.2.fwsc")))
        #expect(!SharedStorage.exists(folder.appending(path: "Zeta.fwsc")))
    }

    @Test func joinsFoldersWhenMovingAndKeepsWhatsAlreadyThere() async throws {
        let source = try Self.folder()
        let destination = try Self.folder()
        for folder in [source, destination] {
            try FileManager.default.createDirectory(
                at: folder.appending(path: ".details"), withIntermediateDirectories: true)
        }
        try Data("new".utf8).write(to: source.appending(path: ".details/a.json"))
        try Data("moved".utf8).write(to: source.appending(path: "Shared.fwsc"))
        try Data("kept".utf8).write(to: destination.appending(path: "Shared.fwsc"))
        try Data("only".utf8).write(to: source.appending(path: "Only.fwsc"))

        await SharedStorage.move(source, into: destination)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: destination.appending(path: ".details/a.json"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: destination.appending(path: "Shared.fwsc"), encoding: .utf8) == "kept")
        #expect(try String(contentsOf: destination.appending(path: "Only.fwsc"), encoding: .utf8) == "only")
    }
}
