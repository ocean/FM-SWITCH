import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// The flash chips a firmware knows, as The Firmware Hub's feed lists them.
struct FlashChipTests {
    private func entry(chip: String?) throws -> CatalogueEntry {
        let field = chip.map { ", \"chip\": \"\($0)\"" } ?? ""
        let json = """
            {"firmwares": [{"id": "zen", "name": "ZEN-1", "kind": ["synth"], "version": "1.2",
            "pkg": "pkg/zen.fwsc", "product": "FM-1_6010200", "size": 1,
            "sha256": "\(String(repeating: "ab", count: 32))"\(field)}]}
            """
        return try #require(HubFeed.decode(Data(json.utf8)).entries().first)
    }

    @Test func readsWhichChipsAFirmwareKnows() throws {
        #expect(try entry(chip: "old").flashChip?.support == .firstChipOnly)
        #expect(try entry(chip: "new").flashChip?.support == .bothChips)
        #expect(try entry(chip: "any").flashChip?.support == .noCheck)
    }

    @Test func leavesTheChipUnknownWhenTheFeedSaysNothingUseful() throws {
        #expect(try entry(chip: nil).flashChip == nil)
        #expect(try entry(chip: "future").flashChip == nil)
    }

    @Test func keepsTheChipWhenTheListIsSaved() throws {
        let entry = try entry(chip: "old")
        let saved = try JSONDecoder().decode(CatalogueEntry.self, from: JSONEncoder().encode(entry))
        #expect(saved.flashChip?.support == .firstChipOnly)
    }
}
