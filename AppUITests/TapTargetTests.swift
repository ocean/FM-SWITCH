import XCTest

// UI tests run on iPhone only: on the Mac, they need the Accessibility permission granted by hand.
#if os(iOS)
    /// Checks that what looks like one control answers a tap anywhere on it, which the accessibility
    /// audit can't tell: it checks each control's size, not whether it covers what it looks like.
    @MainActor
    final class TapTargetTests: XCTestCase {
        override func setUp() {
            continueAfterFailure = false
        }

        /// The Details card on a firmware's page opens from anywhere on it, not just its arrow.
        func testDetailsOpenFromAnywhereOnTheCard() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "standard", "-acknowledgedNoticeVersion", "99", "-tipNudgesShown", "99", "-openPage",
                "firmwares",
            ]
            app.launch()
            let firmware = app.buttons.matching(identifier: "firmware").firstMatch
            XCTAssertTrue(firmware.waitForExistence(timeout: 20))
            firmware.tap()

            let details = app.buttons["Details"]
            XCTAssertTrue(details.waitForExistence(timeout: 10))
            details.swipeUpUntilHittable(in: app)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(details.frame.width, window.width * 0.8, "The header should span the card.")
            XCTAssertGreaterThanOrEqual(details.frame.height, 44)

            // Halfway along, well away from both the label and the arrow.
            details.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["SHA-256"].waitForExistence(timeout: 5))
        }
    }

    extension XCUIElement {
        /// Scrolls up until the element can be tapped, for a part of the page below the fold.
        fileprivate func swipeUpUntilHittable(in app: XCUIApplication) {
            for _ in 0..<6 where !isHittable {
                app.swipeUp()
            }
        }
    }
#endif
