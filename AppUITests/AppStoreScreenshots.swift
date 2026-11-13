import XCTest

// UI tests run on iPhone only, like the accessibility audit; this one runs on iPad too, by hand.
#if os(iOS)
    /// The App Store's screenshots, with the simulated FM-1: the most installed grooveboxes, a few
    /// firmwares' pages, and installing AMB-1, from the checklist to done.
    ///
    /// It runs only when asked, with the folder to write to:
    ///
    ///     TEST_RUNNER_FMSWITCH_SCREENSHOTS=<folder> xcodebuild test ... \
    ///         -only-testing:FMSwitchUITests/AppStoreScreenshots
    @MainActor
    final class AppStoreScreenshots: XCTestCase {
        private var folder = URL(filePath: "/")
        private var prefix = ""
        private var isPad: Bool { prefix == "ipad" }

        override func setUpWithError() throws {
            let path = ProcessInfo.processInfo.environment["FMSWITCH_SCREENSHOTS"]
            try XCTSkipUnless(path != nil, "Only for the App Store's screenshots.")
            folder = URL(filePath: path ?? "/")
            prefix = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            continueAfterFailure = false
        }

        func testListsGrooveboxes() {
            let app = launch(opening: "firmwares", "-firmwareOrder", "installs")
            let grooveboxes = app.buttons["Grooveboxes"]
            XCTAssertTrue(grooveboxes.waitForExistence(timeout: 20))
            grooveboxes.tap()
            // Part way down, so the filter shows above firmwares well into the list.
            let list = app.scrollViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            if isPad { row(app, "SLOOP").tap() }
            sleep(4)
            save(app, "20-grooveboxes")
        }

        func testShowsFirmwarePages() {
            for (id, name) in [("sloop", "SLOOP"), ("jiant", "JIANT FM"), ("x0x", "X0X")] {
                let app = open(id: id, name: name)
                save(app, "21-page-\(id)")
                app.terminate()
            }
        }

        func testInstallsAFirmware() {
            let app = open(id: "amb", name: "AMB-1")
            app.buttons["Install AMB-1"].tap()

            let sheet = app.navigationBars["Before you start"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 30))
            for start in ["It's plugged in", "I'll leave it plugged in", "I've saved", "I'll try it"] {
                let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", start)).firstMatch
                if row.exists { row.tap() }
            }
            save(app, "23-before-you-start")
            let start = app.buttons.matching(NSPredicate(format: "label == 'Install AMB-1' AND enabled == true"))
                .element(boundBy: 0)
            XCTAssertTrue(start.waitForExistence(timeout: 5), "Some of the checklist wasn't ticked.")
            start.tap()

            // Partway through, the progress shows best.
            sleep(9)
            save(app, "24-installing")
            let done = app.staticTexts["AMB-1 is ready to play"]
            XCTAssertTrue(done.waitForExistence(timeout: 180))
            save(app, "25-done")
        }

        /// Opens a firmware's page: straight there on iPhone, or on iPad from the list, filtered to
        /// its kind and with the most installed first, so it's near the top.
        private func open(id: String, name: String) -> XCUIApplication {
            let app = launch(opening: isPad ? "firmwares" : id, "-firmwareOrder", "installs")
            if isPad {
                // The list remembers its filter, so it may be on already.
                let kind = app.buttons[id == "amb" ? "Synths" : "Grooveboxes"].firstMatch
                XCTAssertTrue(kind.waitForExistence(timeout: 20))
                if !kind.isSelected { kind.tap() }
                row(app, name).tap()
            }
            XCTAssertTrue(app.buttons["Install \(name)"].waitForExistence(timeout: 20))
            // Time for the README's pictures to load.
            sleep(5)
            return app
        }

        private func launch(opening page: String, _ arguments: String...) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments =
                [
                    "-look", "standard", "-appearance", "light", "-acknowledgedNoticeVersion", "99",
                    "-tipNudgesShown", "99", "-transport", "simulated", "-openPage", page,
                ] + arguments
            app.launch()
            return app
        }

        private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            return row
        }

        private func save(_ app: XCUIApplication, _ name: String) {
            let url = folder.appending(path: "\(prefix)-\(name).png")
            try? app.screenshot().pngRepresentation.write(to: url)
        }
    }
#endif
