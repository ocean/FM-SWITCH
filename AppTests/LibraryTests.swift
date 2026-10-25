import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// The on-phone library's built-in official firmware.
@MainActor
struct LibraryTests {
    static func emptyDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    @Test func comesWithTheOfficialFirmwareAndKeepsItWhenCleared() throws {
        let library = FirmwareLibrary(directory: Self.emptyDirectory())
        let official = try #require(library.official)
        #expect(official.sha256 == OfficialFirmware.v15.sha256)
        #expect(official.product == "FM-1_015")
        #expect(official.author == "M-VAVE")

        library.clear()
        #expect(library.official == official)
    }

    /// Devices sharing the folder in iCloud Drive would each add a copy otherwise.
    @Test func readsTheBuiltInCopyFromTheAppRatherThanSavingIt() throws {
        let directory = Self.emptyDirectory()
        let library = FirmwareLibrary(directory: directory)
        let official = try #require(library.official)
        #expect(library.items == [official])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(library.url(for: official) == FirmwareLibrary.bundledOfficialURL)
        // So neither look offers to remove it.
        #expect(!library.canRemove(official))
        library.remove(official)
        #expect(library.official == official)
    }

    @Test func savesPackagesUnderTheirNamesWithTheirDetailsBeside() throws {
        let directory = Self.emptyDirectory()
        let library = FirmwareLibrary(directory: directory)
        let item = try FlashingTests.save("FM-1_916", in: library)
        #expect(item.fileName.hasSuffix(".fwsc"))
        #expect(!item.fileName.hasPrefix(String(item.sha256.prefix(16))))
        let details = directory.appending(path: ".details/\(item.sha256).json")
        #expect(FileManager.default.fileExists(atPath: details.path))

        library.remove(item)
        #expect(!FileManager.default.fileExists(atPath: details.path))
        #expect(!FileManager.default.fileExists(atPath: library.url(for: item).path))
    }

    /// What another device sharing the folder saved shows up when the folder's read again.
    @Test func picksUpFirmwaresAnotherDeviceSaved() async throws {
        let directory = Self.emptyDirectory()
        let thisDevice = FirmwareLibrary(directory: directory)
        let otherDevice = FirmwareLibrary(directory: directory)
        let item = try FlashingTests.save("FM-1_916", in: otherDevice)
        #expect(!thisDevice.items.contains(item))
        thisDevice.reload()
        #expect(thisDevice.items.contains(item))
        #expect(try await thisDevice.loadPackage(item).product == "FM-1_916")
    }

    /// Moving into iCloud Drive, here into another folder, takes every saved firmware along.
    @Test func movesItsFirmwaresToANewFolder() async throws {
        let library = FirmwareLibrary(directory: Self.emptyDirectory())
        let item = try FlashingTests.save("FM-1_916", in: library)
        let newDirectory = Self.emptyDirectory()
        await library.move(to: newDirectory)
        #expect(library.directory == newDirectory)
        #expect(library.items.contains(item))
        #expect(FileManager.default.fileExists(atPath: newDirectory.appending(path: item.fileName).path))
    }

    @Test func picksThePackagesThatCanFinishALoadersUpdate() throws {
        let library = FirmwareLibrary(directory: Self.emptyDirectory())
        let official = try #require(library.official)
        let stockLoader = try #require(FM1Identity(text: "ota-FM-1_015"))
        let otherLoader = try #require(FM1Identity(text: "ota-FM-1_900"))
        #expect(library.packages(thatCanFinish: stockLoader) == [official])
        #expect(library.packages(thatCanFinish: otherLoader).isEmpty)
    }

    @Test func picksThePackageAnArmedOpenFirmwaresLoaderIsWaitingFor() throws {
        let library = FirmwareLibrary(directory: Self.emptyDirectory())
        let official = try #require(library.official)
        // Open firmware armed with V15 starts a loader named after the start of V15's build ID.
        let armedForV15 = try #require(FM1Identity(text: "ota-FM1C_db1642b2b6fa5c2c"))
        let armedForOther = try #require(FM1Identity(text: "ota-FM1C_0123456789abcdef"))
        #expect(library.packages(thatCanFinish: armedForV15) == [official])
        #expect(library.packages(thatCanFinish: armedForOther).isEmpty)
    }

    @Test func recognisesOpenFirmwareIdentities() {
        #expect(OpenFirmware.isOpen("FM-1_8000012"))
        #expect(OpenFirmware.isOpen("FM1_OFFICIAL_OPEN"))
        #expect(OpenFirmware.isOpen("FM1_COMMUNITY_3"))
        #expect(!OpenFirmware.isOpen("FM-1_015"))
        #expect(!OpenFirmware.isOpen("FM-1_916"))
        #expect(!OpenFirmware.isOpen("ota-FM-1_8000012"))
    }
}
