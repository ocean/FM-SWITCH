@_spi(Testing) import FM1Kit
import Foundation
import Testing

@testable import FMSwitch

/// The logic behind the standard look: install progress, the device in plain words, firmware
/// badges and the look settings.
@MainActor
struct StandardLookTests {
    static func job(steps count: Int = 1) throws -> DeviceController.FlashJob {
        let library = FirmwareLibrary(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let steps = try (0..<count).map { index in
            try FlashingTests.save("FM-1_9\(10 + index)", in: library)
        }
        return DeviceController.FlashJob(steps: steps)
    }

    @Test func progressRunsThroughTheStagesInOrder() throws {
        var job = try Self.job()
        var seen: [FMSwitch.InstallProgress] = []
        for phase: DeviceController.FlashPhase in [
            .preparing, .staging(requests: 40), .waitingForLoader, .writing(fraction: 0.5),
            .secondPass(fraction: 0.5), .rebooting, .succeeded("FM-1_910"),
        ] {
            job.phase = phase
            seen.append(FMSwitch.InstallProgress(job))
        }
        #expect(seen.map(\.fraction) == seen.map(\.fraction).sorted())
        #expect(
            seen.map(\.stage) == [
                .gettingReady, .gettingReady, .gettingReady, .installing, .installing, .restarting, .restarting,
            ])
        #expect(seen.last?.fraction == 1)
    }

    @Test func installEventsPassOnlyProgressThatMovesTheBar() {
        let filter = InstallEventFilter()
        let reads = (0...1_000).map { UpdateEvent.writing(fraction: Double($0) / 1_000, requests: $0) }
        let passed = reads.compactMap { filter.filter($0)?.event }
        #expect(passed.count < 250)
        #expect(passed.last == reads.last)
        // Every other event is passed on, the second pass's first read included.
        #expect(filter.filter(.checking(fraction: 0, requests: 1))?.event == .checking(fraction: 0, requests: 1))
        let rebooting = filter.filter(.rebooting)
        #expect(rebooting?.event == .rebooting)
        #expect(rebooting?.quiet != nil)
    }

    @Test func aLoaderThatReadsTwiceGetsHalfTheBarForEachPass() throws {
        var job = try Self.job()
        job.loaderReadsTwice = true
        job.phase = .writing(fraction: 1)
        let firstPass = FMSwitch.InstallProgress(job).fraction
        job.phase = .secondPass(fraction: 0.5)
        let halfway = FMSwitch.InstallProgress(job).fraction
        #expect(abs(firstPass - 0.53) < 0.001)
        #expect(abs(halfway - 0.74) < 0.001)
    }

    @Test func progressSpreadsAcrossTheSteps() throws {
        var job = try Self.job(steps: 2)
        job.phase = .succeeded("")
        #expect(FMSwitch.InstallProgress(job).fraction == 0.5)
        job.index = 1
        job.phase = .writing(fraction: 0)
        #expect(FMSwitch.InstallProgress(job).fraction > 0.5)
    }

    @Test func trackerNeverGoesBackwards() throws {
        var job = try Self.job()
        var tracker = FMSwitch.InstallProgress.Tracker()
        job.phase = .writing(fraction: 0.6)
        tracker.update(with: job)
        let reached = tracker.current.fraction

        // A resumed write starts its phase again from nothing.
        job.phase = .preparing
        tracker.update(with: job)
        job.phase = .writing(fraction: 0.1)
        tracker.update(with: job)
        #expect(tracker.current.fraction == reached)

        job.phase = .failed("Unplugged", canResume: true)
        tracker.update(with: job)
        #expect(tracker.current.fraction == reached)
    }

    @Test func soundsShowTheirStageWhenTheyAreWritten() throws {
        var job = try Self.job()
        var tracker = FMSwitch.InstallProgress.Tracker()
        job.phase = .secondPass(fraction: 1)
        tracker.update(with: job)
        #expect(!tracker.showsSounds)

        // The loader writes them before restarting.
        job.phase = .writingResources(fraction: 0.5)
        tracker.update(with: job)
        #expect(tracker.showsSounds)
        #expect(tracker.current.stage == .writingSounds)
        job.phase = .rebooting
        tracker.update(with: job)
        #expect(tracker.current.stage == .restarting)

        // The new firmware writes them once it's running, without the bar going back.
        let reached = tracker.current.fraction
        job.phase = .writingResources(fraction: 0.2)
        tracker.update(with: job)
        #expect(tracker.current.stage == .writingSounds)
        #expect(tracker.current.fraction == reached)
    }

    @Test func summarySaysWhatTheFM1IsDoing() {
        #expect(DeviceSummary(state: .notConnected, identity: nil).statusLine == "Not connected")
        let running = DeviceSummary(state: .running(name: "SLOOP 2.7.1"), identity: "FM-1_900")
        #expect(running.statusLine == "Connected, running SLOOP 2.7.1")
        #expect(running.screenTitle == "SLOOP 2.7.1")
        let unknown = DeviceSummary(state: .running(name: nil), identity: "FM-1_900")
        #expect(unknown.statusLine == "Connected, reporting FM-1_900")
        let official = DeviceSummary(state: .running(name: "the official firmware (V15)"), identity: "FM-1_015")
        #expect(official.screenTitle == "V15")
    }

    @Test func badgeLettersComeFromTheName() {
        #expect(FirmwareBadgeDesign.letters(of: "Felucca") == "Fe")
        #expect(FirmwareBadgeDesign.letters(of: "SLOOP DX7 Banks") == "SB")
        #expect(FirmwareBadgeDesign.letters(of: "M-VAVE official firmware") == "MV")
        #expect(FirmwareBadgeDesign.letters(of: "AMB-1") == "A1")
        #expect(FirmwareBadgeDesign.letters(of: "AMB-1 Evolved") == "AE")
        #expect(FirmwareBadgeDesign.letters(of: "AmbWave") == "AW")
        #expect(FirmwareBadgeDesign.letters(of: "386DX") == "38")
        #expect(FirmwareBadgeDesign.letters(of: "SLOOP") == "SL")
        #expect(FirmwareBadgeDesign.letters(of: "fm1-mdx") == "Md")
        #expect(FirmwareBadgeDesign.letters(of: "fm1-rocket-os") == "RO")
        #expect(FirmwareBadgeDesign.letters(of: "") == "?")
    }

    @Test func badgesKeepToTheirNames() {
        // The same on every launch, unlike `hashValue`.
        #expect(FirmwareBadgeDesign.seed(of: "Felucca") == 4_087_215_988)
        // Case and punctuation don't change it, but a new name does.
        #expect(FirmwareBadgeDesign(name: "felucca!") == FirmwareBadgeDesign(name: "Felucca"))
        let felucca = FirmwareBadgeDesign(name: "Felucca")
        let felucca2 = FirmwareBadgeDesign(name: "Felucca 2")
        #expect([felucca2.first, felucca2.second] != [felucca.first, felucca.second])
    }

    /// Every pair of 16 hues at least five apart, either half light, in two tones and two shapes.
    @Test func badgesComeIn896Designs() {
        let designs = (0..<20000).map { FirmwareBadgeDesign(name: "Firmware \($0)") }
        let colourings = Set(designs.map { "\($0.first) \($0.second) \($0.split)" })
        #expect(colourings.count == 896)
    }

    /// One half is light and the other dark, so a badge never reads as one muddy colour.
    @Test func aBadgesHalvesContrast() {
        for index in 0..<2000 {
            let design = FirmwareBadgeDesign(name: "Firmware \(index)")
            #expect(Contrast.ratio(design.first, design.second) >= 1.4, "\(design.first) \(design.second)")
        }
    }

    @Test func theOfficialBadgeShowsItsVersion() {
        let official = FirmwareBadgeDesign(name: "M-VAVE official firmware", isOfficial: true, version: "V15")
        #expect(official.letters == "V15")
        #expect(
            FirmwareBadgeDesign(name: "M-VAVE official firmware", isOfficial: true, version: "V16").letters == "V16")
        #expect(FirmwareBadgeDesign(name: "M-VAVE official firmware", isOfficial: true).letters == "MV")
    }

    @Test func looksAndAppearanceAreRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.look == .standard)
        #expect(settings.appearance == .system)
        #expect(!settings.isRetroFound)

        settings.look = .retro
        settings.appearance = .dark
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.look == .retro)
        #expect(reopened.appearance == .dark)
        // Anyone already using Retro has found it.
        #expect(reopened.isRetroFound)
        #expect(AppSettings.savedLook(in: defaults) == .retro)
    }
}
