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
        #expect(try entry(chip: "old").flashChip == .old)
        #expect(try entry(chip: "new").flashChip == .new)
        #expect(try entry(chip: "any").flashChip == .any)
    }

    @Test func leavesTheChipUnknownWhenTheFeedSaysNothingUseful() throws {
        #expect(try entry(chip: nil).flashChip == nil)
        #expect(try entry(chip: "future").flashChip == nil)
    }

    @Test func onlyTheOlderChipIsRiskyOnNewerUnits() {
        #expect(FlashChipSupport.old.isRiskyOnNewerUnits)
        #expect(!FlashChipSupport.new.isRiskyOnNewerUnits)
        #expect(!FlashChipSupport.any.isRiskyOnNewerUnits)
    }
}
