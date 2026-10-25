import XCTest
import XCUIAutomation

// UI tests run on iPhone only: on the Mac, they need the Accessibility permission granted by hand,
// and the audit's text size and clipped text checks are iOS-only.
#if os(iOS)
    extension XCUIApplication {
        /// Every check but Dynamic Type's.
        ///
        /// That check flags text that grows but gets cut short as the audit enlarges it on its own.
        /// The large-text runs check text at a large size as it's actually drawn instead, and
        /// SwiftLint's `dynamic_type` rule keeps fixed sizes out.
        private static let auditTypes = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)

        /// Runs Apple's accessibility audit on what's on screen, skipping what VoiceOver never
        /// reaches or what's cut short on purpose.
        ///
        /// - Parameters:
        ///   - skipped: Checks to leave out, on top of Dynamic Type's.
        ///   - floating: Where something floats over the page, with its shadow. Text it overlaps is
        ///     partly hidden or shaded on purpose, so its contrast isn't checked.
        ///   - isClearOfSearchField: Whether nothing on the firmware list is under its search field,
        ///     so contrast issues the audit can't place are failures there too.
        /// - Throws: If the audit can't run; the issues it finds are recorded as test failures.
        func auditStandardLook(
            skipping skipped: XCUIAccessibilityAuditType = [],
            floating: [CGRect] = [],
            isClearOfSearchField: Bool = false
        ) throws {
            // Illustrations are one image to VoiceOver, but XCUITest still lists the text inside them.
            let decorative = descendants(matching: .any).matching(identifier: "decorative")
            let illustrations = decorative.allElementsBoundByIndex.map(\.frame)
            let screen = windows.firstMatch.frame
            // On the firmware list, the search field floats over the bottom of the screen.
            let searchFieldArea =
                navigationBars["Firmwares"].exists ? screen.maxY - 108 : .infinity
            let types = Self.auditTypes.subtracting(skipped)
            // Whether an issue is one of those above, which isn't a failure.
            let isExpected = { (issue: XCUIAccessibilityAuditIssue) -> Bool in
                guard let element = issue.element else {
                    // On the firmware list, text blurred under the search field is reported with no
                    // element to place it, so a short list is audited too, clear of it.
                    return issue.auditType == .contrast && searchFieldArea.isFinite && !isClearOfSearchField
                }
                let frame = element.frame
                if illustrations.contains(where: { $0.contains(frame) }) { return true }
                // Text under the search field, or scrolled out of view behind a button, can't be
                // read there, so it can't fail contrast there.
                if issue.auditType == .contrast, frame.maxY > searchFieldArea || !element.isHittable { return true }
                // A filter in a row that scrolls sideways can be cut off by the screen's edge, and
                // reads in full once scrolled to.
                if issue.auditType == .contrast, frame.minX < screen.minX || frame.maxX > screen.maxX { return true }
                if issue.auditType == .contrast, floating.contains(where: { $0.intersects(frame) }),
                    !floating.contains(where: { $0.contains(frame) })
                {
                    return true
                }
                // Each firmware's summary is cut to two lines in the list, and shown in full on its page.
                return issue.auditType == .textClipped && element.identifier == "summary"
            }
            // Text still fading in fails contrast, and on CI's machines, which draw without a graphics
            // card, a fade can take seconds. So the audit looks again after a pause, a few times,
            // before it records what it finds.
            for _ in 0..<3 {
                var isClear = true
                try performAccessibilityAudit(for: types) { issue in
                    if !isExpected(issue) { isClear = false }
                    return true
                }
                if isClear { return }
                _ = XCTWaiter.wait(for: [XCTestExpectation(description: "The screen settles.")], timeout: 1)
            }
            try performAccessibilityAudit(for: types) { issue in
                if isExpected(issue) { return true }
                // The failure only says what kind of issue it is, so this says where.
                if let element = issue.element {
                    print("Accessibility audit: \(issue.compactDescription): '\(element.label)' at \(element.frame)")
                } else {
                    print("Accessibility audit: \(issue.compactDescription), with no element")
                }
                return false
            }
        }
    }
#endif
