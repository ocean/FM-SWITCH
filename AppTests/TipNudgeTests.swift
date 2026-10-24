import Testing

@testable import FMSwitch

/// When the tip card slides up.
struct TipNudgeTests {
    @Test func waitsForTheFifthInstall() {
        #expect(TipNudge.due(installs: 4, shown: 0) == nil)
        #expect(TipNudge.due(installs: 5, shown: 0) == .fifthInstall)
    }

    @Test func comesBackAtTheFifteenth() {
        #expect(TipNudge.due(installs: 14, shown: 1) == nil)
        #expect(TipNudge.due(installs: 15, shown: 1) == .fifteenthInstall)
        #expect(TipNudge.due(installs: 30, shown: 2) == nil)
    }

    @Test func showsOnlyTheLatestWhenOneWasMissed() {
        #expect(TipNudge.due(installs: 15, shown: 0) == .fifteenthInstall)
        #expect(TipNudge.reached(installs: 15).count == 2)
    }
}
