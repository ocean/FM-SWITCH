import XCTest

// UI tests run on iPhone only: on the Mac, they need the Accessibility permission granted by hand.
#if os(iOS)
    /// Checks that pulling the firmware list down to refresh it, again and again, leaves the list
    /// where it started, as testers found it stuck pulled down after a few pulls.
    @MainActor
    final class PullToRefreshTests: XCTestCase {
        override func setUp() {
            continueAfterFailure = false
        }

        func testTheListSettlesAfterPullingAgainAndAgain() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "standard", "-acknowledgedNoticeVersion", "99", "-tipNudgesShown", "99", "-openPage",
                "firmwares",
            ]
            app.launch()
            let firmware = app.buttons.matching(identifier: "firmware").firstMatch
            XCTAssertTrue(firmware.waitForExistence(timeout: 20))
            let top = firmware.frame.minY

            // Pulls close together, some while the last refresh is still running, and some after.
            for (hold, pause) in [(0.0, 0.3), (0.0, 0.3), (1.0, 2.0), (0.5, 0.5), (2.0, 3.0), (0.0, 0.2), (1.5, 0.1)] {
                let start = firmware.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                start.press(
                    forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 400)),
                    withVelocity: .slow,
                    thenHoldForDuration: hold
                )
                Thread.sleep(forTimeInterval: pause)
            }

            let settled = expectation(
                for: NSPredicate { _, _ in abs(firmware.frame.minY - top) < 2 }, evaluatedWith: nil)
            wait(for: [settled], timeout: 30)
        }
    }
#endif
