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

    @Test func theWayRoundGoesThroughMIDIMON() {
        let paragraphs = HelpTopic.wontInstall.paragraphs
        #expect(paragraphs.contains { $0.contains("First install MIDIMON 0.5.") })
        #expect(paragraphs.last?.hasPrefix("If that doesn't work,") == true)
    }
}
