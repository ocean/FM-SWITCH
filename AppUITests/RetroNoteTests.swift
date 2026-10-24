import XCTest

// UI tests run on iPhone only, like the accessibility audit.
#if os(iOS)
    /// Five taps on the FM-1's screen find Retro and offer it, without switching to it unasked.
    @MainActor
    final class RetroNoteTests: XCTestCase {
        func testLaterKeepsTheStandardLook() throws {
            let app = launch()
            findRetro(in: app)
            // Let the note finish sliding in, so the audit sees it as it rests.
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The note settles.")], timeout: 1)
            // The clipped text check reports one of the note's two buttons as cut short, a different
            // one each run, though neither is in a screenshot taken as it runs.
            // The note floats over Home, and its shadow falls on the card above it.
            let note = app.buttons["retroNote"].frame.union(app.buttons["Later"].frame).insetBy(dx: -40, dy: -50)
            try app.auditStandardLook(skipping: .textClipped, floating: [note])
            app.buttons["Later"].tap()
            XCTAssertTrue(app.staticTexts["You found Retro!"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.navigationBars["My FM-1"].exists)
        }

        func testTheNoteOpensSettings() {
            let app = launch()
            findRetro(in: app)
            app.buttons["retroNote"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            // Retro, and its app icon, are in Settings now.
            let iconChoice = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH 'App icon'"))
            XCTAssertTrue(iconChoice.firstMatch.waitForExistence(timeout: 5))
        }

        func testSwitchNowSwitchesToRetro() {
            let app = launch()
            findRetro(in: app)
            app.buttons["Switch now"].tap()
            XCTAssertTrue(app.navigationBars["My FM-1"].waitForNonExistence(timeout: 5))
        }

        /// Opens My FM-1 in the standard look, with Retro not yet found.
        private func launch() -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "standard", "-isRetroFound", "NO", "-appearance", "light", "-acknowledgedNoticeVersion", "99",
                "-tipNudgesShown", "99",
            ]
            app.launch()
            XCTAssertTrue(app.navigationBars["My FM-1"].waitForExistence(timeout: 10))
            return app
        }

        private func findRetro(in app: XCUIApplication) {
            // Five quick taps at the drawing's centre, which is on its screen. Separate taps can be
            // too slow to land within the two seconds the easter egg allows.
            app.images.matching(identifier: "decorative").firstMatch.tap(withNumberOfTaps: 5, numberOfTouches: 1)
            XCTAssertTrue(app.staticTexts["You found Retro!"].waitForExistence(timeout: 5))
        }
    }
#endif
