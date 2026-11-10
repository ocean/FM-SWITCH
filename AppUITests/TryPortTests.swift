import XCTest

// UI tests run on iPhone only, like the accessibility audit.
#if os(iOS)
    /// Finding an FM-1 whose firmware gives its USB port another name, by trying the port.
    @MainActor
    final class TryPortTests: XCTestCase {
        func testFindsAnFM1OnAPortTried() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "standard", "-acknowledgedNoticeVersion", "99", "-tipNudgesShown", "99",
                "-transport", "simulated", "-simulatedRenamedPort", "YES", "-triedPortNames", "()",
            ]
            app.launch()
            XCTAssertTrue(app.staticTexts["Not connected"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Groovebox MIDI"].exists)
            let tryPort = app.buttons["tryPort"]
            XCTAssertTrue(tryPort.waitForExistence(timeout: 5))
            tryPort.tap()
            let confirm = app.buttons
                .matching(NSPredicate(format: "label == 'Try This Port' AND identifier != 'tryPort'"))
                .firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            confirm.tap()
            XCTAssertTrue(app.staticTexts["Not connected"].waitForNonExistence(timeout: 15))
        }

        /// Retro asks before trying a port too.
        func testRetroAsksBeforeTryingAPort() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "retro", "-acknowledgedNoticeVersion", "99", "-tipNudgesShown", "99",
                "-transport", "simulated", "-simulatedRenamedPort", "YES", "-triedPortNames", "()",
            ]
            app.launch()
            let tryPort = app.buttons["TRY THIS PORT"]
            XCTAssertTrue(tryPort.waitForExistence(timeout: 15))
            while !tryPort.isHittable { app.swipeUp() }
            tryPort.tap()
            let confirm = app.buttons["Try This Port"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.buttons["STOP TRYING"].waitForExistence(timeout: 15))
        }
    }
#endif
