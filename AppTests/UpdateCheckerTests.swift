#if os(macOS)
    import Foundation
    import Testing

    @testable import FMSwitch

    /// Checking GitHub for a newer FM-SWITCH, on the Mac.
    @MainActor
    struct UpdateCheckerTests {
        /// GitHub's answer for a release with this tag.
        nonisolated private static func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
            Data(
                """
                {"tag_name": "\(tag)", "html_url": "https://github.com/ocean/FM-SWITCH/releases/tag/\(tag)",
                 "draft": \(draft), "prerelease": \(prerelease), "name": "FM-SWITCH \(tag)"}
                """.utf8)
        }

        private static func checker(
            current: String = "0.1.0",
            defaults: UserDefaults? = nil,
            now: @escaping () -> Date = Date.init,
            answer: @escaping @Sendable () throws -> Data
        ) throws -> UpdateChecker {
            let defaults = try defaults ?? #require(UserDefaults(suiteName: UUID().uuidString))
            return UpdateChecker(current: current, defaults: defaults, fetch: { _ in try answer() }, now: now)
        }

        @Test func versionsCompareNumberByNumber() {
            #expect(UpdateChecker.isNewer("0.2.0", than: "0.1.0"))
            #expect(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
            #expect(UpdateChecker.isNewer("1.0.1", than: "1.0"))
            #expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"))
            #expect(!UpdateChecker.isNewer("0.1.0", than: "0.2.0"))
            #expect(!UpdateChecker.isNewer("0.2.0-beta", than: "0.1.0"))
        }

        @Test func tagsMayStartWithV() {
            #expect(UpdateChecker.version(fromTag: "v0.2.0") == "0.2.0")
            #expect(UpdateChecker.version(fromTag: "0.2.0") == "0.2.0")
            #expect(UpdateChecker.version(fromTag: "mac-0.2.0") == nil)
            #expect(UpdateChecker.version(fromTag: "0.2.") == nil)
        }

        @Test func aNewerReleaseIsOffered() async throws {
            let checker = try Self.checker { Self.release("v0.2.0") }
            let expected = AppRelease(
                version: "0.2.0", page: URL(literal: "https://github.com/ocean/FM-SWITCH/releases/tag/v0.2.0"))
            #expect(await checker.check() == .newer(expected))
            #expect(checker.available == expected)
        }

        @Test func theSameVersionIsTheLatest() async throws {
            let checker = try Self.checker { Self.release("0.1.0") }
            #expect(await checker.check() == .latest)
            #expect(checker.available == nil)
        }

        @Test func draftsAndPreReleasesArentOffered() async throws {
            let draft = try Self.checker { Self.release("0.2.0", draft: true) }
            #expect(await draft.check() == .failed)
            let preRelease = try Self.checker { Self.release("0.2.0", prerelease: true) }
            #expect(await preRelease.check() == .failed)
            #expect(draft.available == nil && preRelease.available == nil)
        }

        @Test func noReleasesYetIsTheLatest() async throws {
            let checker = try Self.checker { throw Network.BadStatus(code: 404) }
            #expect(await checker.check() == .latest)
        }

        @Test func beingOfflineFails() async throws {
            let checker = try Self.checker { throw URLError(.notConnectedToInternet) }
            #expect(await checker.check() == .failed)
        }

        @Test func notNowWaitsForTheNextVersion() async throws {
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            var checker = try Self.checker(defaults: defaults) { Self.release("0.2.0") }
            await checker.check()
            checker.notNow()
            #expect(checker.available == nil)

            // Still hidden when the app opens again.
            checker = try Self.checker(defaults: defaults) { Self.release("0.3.0") }
            #expect(checker.available == nil)
            await checker.check()
            #expect(checker.available?.version == "0.3.0")
        }

        @Test func aReleaseFoundEarlierIsRemembered() async throws {
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            try await Self.checker(defaults: defaults) { Self.release("0.2.0") }.check()
            #expect(try Self.checker(defaults: defaults) { Data() }.available?.version == "0.2.0")
            // Once this app is that version, it's gone.
            #expect(try Self.checker(current: "0.2.0", defaults: defaults) { Data() }.available == nil)
        }

        @Test func itChecksByItselfOnceADay() async throws {
            let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
            let start = Date()
            var clock = start
            let asked = Counter()
            let checker = try Self.checker(
                defaults: defaults,
                now: { clock },
                answer: {
                    asked.add()
                    return Self.release("0.2.0")
                })
            await checker.checkIfDue()
            clock = start.addingTimeInterval(60 * 60)
            await checker.checkIfDue()
            #expect(asked.count == 1)
            clock = start.addingTimeInterval(UpdateChecker.interval + 1)
            await checker.checkIfDue()
            #expect(asked.count == 2)

            checker.checksAutomatically = false
            clock = start.addingTimeInterval(3 * UpdateChecker.interval)
            await checker.checkIfDue()
            #expect(asked.count == 2)
        }
    }

    /// Counts calls from a `@Sendable` closure.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int { lock.withLock { value } }

        func add() { lock.withLock { value += 1 } }
    }
#endif
