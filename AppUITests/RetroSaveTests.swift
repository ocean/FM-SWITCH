import XCTest

// UI tests run on iPhone only, like the accessibility audit.
#if os(iOS)
    /// Save my FM-1 in Retro, with the simulated FM-1 on M-VAVE's open firmware.
    @MainActor
    final class RetroSaveTests: XCTestCase {
        func testSavesFromTheDeviceScreen() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-look", "retro", "-acknowledgedNoticeVersion", "99", "-tipNudgesShown", "99",
                "-simulatedOpenFirmware", "YES",
            ]
            app.launch()
            let open = app.buttons["SAVE MY FM-1"]
            XCTAssertTrue(open.waitForExistence(timeout: 15))
            open.tap()
            let save = app.buttons["SAVE"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            save.tap()
            let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'SAVED:'")).firstMatch
            XCTAssertTrue(saved.waitForExistence(timeout: 30))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["CLOSE"].tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        }
    }
#endif
