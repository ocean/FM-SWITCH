import Testing

@testable import FMSwitch

/// What the Help page says.
@MainActor
struct HelpTopicTests {
    @Test func lightningAdaptersAreOnlyMentionedOnIOS() {
        let mentions = HelpTopic.notSeen.paragraphs.contains { $0.contains("Lightning to USB Camera Adapter") }
        #if os(macOS)
            #expect(!mentions)
        #else
            #expect(mentions)
        #endif
    }

    @Test func theWayRoundGoesThroughMIDIMONOrLOOM8() {
        let paragraphs = HelpTopic.wontInstall.paragraphs
        #expect(paragraphs.contains { $0.contains("First install MIDIMON 0.4 or LOOM-8 0.8.") })
        #expect(paragraphs.last?.hasPrefix("If that doesn't work,") == true)
    }
}
