import XCTest

// The audit runs on iPhone only: on the Mac, UI tests need the Accessibility permission granted by
// hand, and its text size and clipped text checks are iOS-only.
#if os(iOS)
    /// Runs Apple's accessibility audit on each of the standard look's main screens, in light mode,
    /// dark mode and at a large text size.
    ///
    /// The audit checks what's actually drawn: contrast, clipped text, elements without labels or
    /// traits, and tap targets that are too small.
    @MainActor
    final class AccessibilityAuditTests: XCTestCase {
        /// The settings each run starts with, passed as launch arguments so they override what's saved.
        enum Setting: CaseIterable {
            case light
            case dark
            case largeText

            var arguments: [String] {
                switch self {
                case .light: ["-appearance", "light"]
                case .dark: ["-appearance", "dark"]
                case .largeText:
                    [
                        "-appearance", "light", "-UIPreferredContentSizeCategoryName",
                        "UICTContentSizeCategoryAccessibilityL",
                    ]
                }
            }
        }

        override func setUp() {
            continueAfterFailure = true
        }

        func testHome() throws {
            for setting in Setting.allCases {
                let app = launch(setting)
                XCTAssertTrue(app.navigationBars["My FM-1"].waitForExistence(timeout: 10), "\(setting)")
                try app.auditStandardLook()
            }
        }

        func testFirmwareList() throws {
            for setting in Setting.allCases {
                let app = launch(setting, page: "firmwares")
                XCTAssertTrue(app.navigationBars["Firmwares"].waitForExistence(timeout: 10), "\(setting)")
                try app.auditStandardLook()
                // A search short enough to leave nothing under the search field, with untested firmwares.
                let search = app.searchFields.firstMatch
                search.tap()
                search.typeText("B1\n")
                XCTAssertTrue(app.staticTexts["B1 Drawbar Organ"].waitForExistence(timeout: 5), "\(setting)")
                try app.auditStandardLook(isClearOfSearchField: true)
            }
        }

        func testSettings() throws {
            for setting in Setting.allCases {
                let app = launch(setting, page: "settings")
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "\(setting)")
                try app.auditStandardLook()
            }
        }

        /// Save my FM-1, ready to save and once it's saved, with the simulated FM-1 on open firmware.
        func testSaveMyFM1() throws {
            for setting in Setting.allCases {
                let app = launch(setting, page: "save", extraArguments: ["-simulatedOpenFirmware", "YES"])
                let save = app.buttons["Save my FM-1"]
                XCTAssertTrue(save.waitForExistence(timeout: 15), "\(setting)")
                try app.auditStandardLook()
                save.tap()
                XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 30), "\(setting)")
                // The page shrinks as it finishes, so it settles before the audit notes where the
                // drawing is.
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The page settles.")], timeout: 1)
                try app.auditStandardLook()
            }
        }

        /// The tip card, as it slides up after the fifth install.
        func testTipNudge() throws {
            for setting in Setting.allCases {
                let app = launch(setting, extraArguments: ["-tipNudgesShown", "0", "-tipNudgeInstalls", "5"])
                XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10), "\(setting)")
                // It waits, then slides up.
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The card settles.")], timeout: 1.5)
                let card = app.otherElements["tipNudge"]
                // Its shadow shades the page around it too.
                try app.auditStandardLook(floating: [card.frame.insetBy(dx: -24, dy: -24)], floatingCard: card)
                app.buttons["Not now"].tap()
                XCTAssertTrue(app.buttons["Not now"].waitForNonExistence(timeout: 5), "\(setting)")
            }
        }

        func testWelcomeNotice() throws {
            for setting in Setting.allCases {
                let app = launch(setting, acknowledgesNotice: false)
                XCTAssertTrue(app.staticTexts["Welcome to FM-SWITCH"].waitForExistence(timeout: 10), "\(setting)")
                try app.auditStandardLook()
            }
        }

        /// Opens the app in the standard look, past the welcome notice unless asked not to.
        private func launch(
            _ setting: Setting, page: String? = nil, acknowledgesNotice: Bool = true, extraArguments: [String] = []
        ) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-look", "standard"] + setting.arguments
            app.launchArguments += ["-acknowledgedNoticeVersion", acknowledgesNotice ? "99" : "0"]
            // The tip card only shows when a test asks for it.
            if !extraArguments.contains("-tipNudgesShown") {
                app.launchArguments += ["-tipNudgesShown", "99"]
            }
            if let page {
                app.launchArguments += ["-openPage", page]
            }
            app.launchArguments += extraArguments
            app.launch()
            return app
        }
    }
#endif
