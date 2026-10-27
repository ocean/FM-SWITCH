import Foundation
import Testing

@testable import FMSwitch

/// Stars, kept in a file other devices can read.
@MainActor
struct StarredFirmwaresTests {
    private static func folder() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    @Test func starsAreKeptInTheFolder() {
        let folder = Self.folder()
        let stars = StarredFirmwares(folder: folder)
        stars.toggle("bop-1")
        stars.toggle("dub")
        stars.toggle("bop-1")
        #expect(stars.ids == ["dub"])
        #expect(StarredFirmwares(folder: folder).ids == ["dub"])
    }

    @Test func anotherDevicesChangesAreReadAgain() throws {
        let folder = Self.folder()
        let stars = StarredFirmwares(folder: folder)
        stars.toggle("dub")
        let file = folder.appending(path: StarredFirmwares.fileName)
        try Data(#"{"starred":["amb","loom-8"]}"#.utf8).write(to: file)
        stars.reload()
        #expect(stars.ids == ["amb", "loom-8"])
        try FileManager.default.removeItem(at: file)
        stars.reload()
        #expect(stars.ids.isEmpty)
    }

    @Test func movingJoinsTheStarsAlreadyThere() async throws {
        let here = Self.folder()
        let there = Self.folder()
        StarredFirmwares(folder: there).toggle("amb")
        let stars = StarredFirmwares(folder: here)
        stars.toggle("dub")
        await stars.move(to: there)
        #expect(stars.ids == ["amb", "dub"])
        #expect(!FileManager.default.fileExists(atPath: here.appending(path: StarredFirmwares.fileName).path))
        #expect(StarredFirmwares(folder: there).ids == ["amb", "dub"])
    }
}
