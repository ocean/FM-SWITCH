import Foundation
import Testing

@testable import FMSwitch

/// Firmware descriptions written in Markdown.
struct FirmwareDescriptionTests {
    @Test func dropsTheMarkdownMarks() {
        #expect(FirmwareDescription.plain("Its **visualiser** paints it") == "Its visualiser paints it")
    }

    @Test func keepsALinksTextButNotTheLink() {
        let styled = FirmwareDescription.styled("See [the site](https://example.com) for more.")
        #expect(String(styled.characters) == "See the site for more.")
        #expect(styled.runs.allSatisfy { $0.link == nil })
    }

    @Test func leavesPlainTextAlone() {
        #expect(FirmwareDescription.plain("Drones that breathe: 6-op FM.") == "Drones that breathe: 6-op FM.")
    }
}
