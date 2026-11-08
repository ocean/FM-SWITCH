import FM1Kit
import Foundation

/// What the check before installing found, from ``InstallReadiness/check(_:on:)``.
enum InstallCheckState: Equatable {
    case checking
    case found(InstallKind)
    /// The FM-1 is in its update loader, so the install finishes that update; there's nothing to
    /// check.
    case finishingUpdate
    case failed(String)
}

/// What FM1Kit's guides say about an install, read from the packages before it starts, by
/// ``read(installing:requiresOfficial:model:)``.
struct SwitchingCheck: Equatable {
    /// Whether the packages have been read yet.
    var isRead = false
    /// The guide to what the FM-1 is running, when it's known.
    var running: LeavingGuide?
    /// The guide to the firmware picked, once it's installed.
    var installed: LeavingGuide?
    /// How the firmware running gets to the first firmware planned.
    var route: LeavingRoute?
    /// Where the first firmware planned takes the FM-1, for the guide's steps.
    var destination: LeavingDestination?
    /// MIDIMON or LOOM-8, to go on first, as the firmware running can't install the one planned.
    var firstStep: StoredFirmware?
    /// Why the firmware to go on first couldn't be had.
    var firstStepProblem: String?
    /// Whether what happens after this firmware depends on a bootloader no install from this app
    /// has shown, so the person is asked what starts their FM-1.
    var dependsOnStartUp = false
    /// Whether V15 goes on after V16, which leaves data behind that makes V15 play one note at a
    /// time until it's erased.
    var followsV16 = false
    /// Whether V16 goes on, after which going back to V15 needs a Mac.
    var installsV16 = false
    /// The firmwares planned that only know the first FM-1s' flash chip, when the FM-1 says it has
    /// the newer one.
    var knowsOnlyFirstChip: [String] = []

    /// Whether the firmware running can't install the one planned directly, so another goes on first.
    var needsFirstStep: Bool { route == .throughFixedFirmware }

    /// What to know before installing, from the guide, and when the FM-1's bootloader isn't
    /// known, what it would say if that's been changed.
    var warnings: [String] {
        guard let installed else { return [] }
        let warnings = SwitchingWords.warnings(installed)
        guard installed.bootArea == nil, SwitchingGuide.dependsOnBootArea(installed.updateCode) else { return warnings }
        let changed = LeavingGuide(
            firmwareName: installed.firmwareName,
            identity: installed.identity,
            updateCode: installed.updateCode,
            bootArea: .mBootloader
        )
        return warnings
            + SwitchingWords.warnings(changed).filter { !warnings.contains($0) }.map { "\(Self.ifChanged) \($0)" }
    }

    /// What a warning that applies only to a changed bootloader starts with.
    static let ifChanged = "If your FM-1's bootloader isn't the one it came with:"

    /// Reads what installing `target` means for switching away again, and finds MIDIMON or
    /// LOOM-8 to go on first when the firmware running can't install it.
    @MainActor
    static func read(installing target: StoredFirmware, requiresOfficial: Bool, model: AppModel) async -> Self {
        var check = Self(isRead: true)
        let device = model.device
        let steps = device.plan(
            for: target, requiresOfficial: requiresOfficial, alwaysViaOfficial: model.settings.alwaysViaOfficial)
        var packages: [FwscPackage] = []
        for step in steps {
            guard let package = try? await model.library.loadPackage(step) else { return check }
            packages.append(package)
        }
        let saved = device.identity.flatMap { model.history.lastInstall(matching: $0.text)?.guide }
        check.running = SwitchingGuide.running(device.identity, saved: saved, startUp: model.settings.startUp)
        check.destination = packages.first.map(LeavingDestination.init(installing:))
        check.route = check.destination.flatMap { check.running?.route(to: $0) }
        check.installsV16 = packages.contains { LeavingDestination(installing: $0) == .v16 }
        if device.hasNewerFlashChip {
            check.knowsOnlyFirstChip = zip(steps, packages).filter { $0.1.flashChipSupport == .firstChipOnly }
                .map(\.0.name)
        }
        check.followsV16 =
            packages.contains { LeavingDestination(installing: $0) == .v15 }
            && (check.running?.identity == .officialV16 || check.running?.bootArea == .v16)
        if check.needsFirstStep {
            do {
                check.firstStep = try await FixedFirmware.find(in: model.library, catalogue: model.catalogue)
            } catch {
                check.firstStepProblem = error.localizedDescription
            }
        }
        var planned = Array(zip(steps, packages))
        if let firstStep = check.firstStep, let package = try? await model.library.loadPackage(firstStep) {
            planned.insert((firstStep, package), at: 0)
        }
        // The guide to the last, as each goes on over the one before.
        func installed(startingFrom running: LeavingGuide?, startUp: StartUp?) -> LeavingGuide? {
            var guide = running
            var last: LeavingGuide?
            for (step, package) in planned {
                last = SwitchingGuide.guide(installing: package, named: step.name, over: guide, startUp: startUp)
                guide = last ?? guide
            }
            return last
        }
        check.installed = installed(startingFrom: check.running, startUp: model.settings.startUp)
        let known = installed(
            startingFrom: SwitchingGuide.running(device.identity, saved: saved, startUp: nil), startUp: nil)
        check.dependsOnStartUp =
            known.map { $0.bootArea == nil && SwitchingGuide.dependsOnBootArea($0.updateCode) } ?? false
        return check
    }
}

/// Whether installing a firmware can start, and what the person has to confirm first: the rules
/// both looks' confirmation screens share.
struct InstallReadiness: Equatable {
    /// What will be installed, in order: MIDIMON or LOOM-8 first when the firmware running can't
    /// install the rest, then the official firmware when it's needed.
    var steps: [StoredFirmware]
    var checked: InstallCheckState
    var identity: FM1Identity?
    /// Whether the official firmware has to go on first, and there's no copy of it.
    var isMissingOfficial: Bool
    /// Whether the firmware is from the list but hasn't been tested on a real FM-1, so the person
    /// has to accept that first.
    var isUntested: Bool
    /// What the guides say about switching away again.
    var switching: SwitchingCheck
    /// What the person says starts their FM-1, or nil until they've been asked.
    var startUp: StartUp?

    /// Why an untested firmware is a risk, for both looks' confirmation screens.
    static let untestedWarning = """
        This firmware is only listed on aroum's FM1 Resource Hub or mutant.cloud, not on The Firmware \
        Hub or fm1-editor.com, so it may not have been well tested on a real FM-1. It may not install, or \
        may not let another firmware install after it. Recovery might need a computer, check \
        this app's settings for further information.
        """

    /// What going back to V15 will take, for both looks' confirmation screens before V16.
    static let beforeV16Warning = """
        Going back to V15 later needs a Mac: after V16, V15 plays one note at a time until it's \
        installed again in FM-SWITCH's Backup & rescue, with Start the new firmware fresh ticked.
        """

    /// What a firmware that only knows the first flash chip does on an FM-1 with the newer one,
    /// for both looks' confirmation screens.
    static func newerFlashChipWarning(_ names: [String]) -> String {
        let name = ListFormatter.localizedString(byJoining: names)
        return """
            Your FM-1 has the newer flash chip, which \(name) doesn't know. On it, \(name) usually keeps \
            changes only until it's switched off, and it often can't install another firmware.
            """
    }

    /// What V15 does after V16, for both looks' confirmation screens.
    #if os(macOS)
        static let afterV16Warning = """
            After V16, V15 plays one note at a time, as V16 leaves data behind that V15 misreads. To \
            clear it, install V15 in Backup & rescue, with Start the new firmware fresh ticked.
            """
    #else
        static let afterV16Warning = """
            After V16, V15 plays one note at a time, as V16 leaves data behind that V15 misreads. To \
            clear it, install V15 from a Mac, in FM-SWITCH's Backup & rescue, with Start the new \
            firmware fresh ticked.
            """
    #endif

    @MainActor
    init(
        target: StoredFirmware,
        requiresOfficial: Bool,
        checked: InstallCheckState,
        switching: SwitchingCheck,
        model: AppModel
    ) {
        let viaOfficial = requiresOfficial || model.settings.alwaysViaOfficial
        let planned = model.device.plan(
            for: target, requiresOfficial: requiresOfficial, alwaysViaOfficial: model.settings.alwaysViaOfficial)
        steps = (switching.firstStep.map { [$0] } ?? []) + planned
        self.checked = checked
        identity = model.device.identity
        isMissingOfficial = viaOfficial && target.source != .official && model.library.official == nil
        let listed = target.catalogueID.flatMap(model.catalogue.listedEntry(id:))
        isUntested = target.source == .catalogue && listed?.isHardwareTested == false
        self.switching = switching
        startUp = model.settings.startUp
    }

    /// Whether the person has to say what starts their FM-1 before this can install.
    var needsStartUp: Bool {
        switching.dependsOnStartUp && startUp == nil
    }

    /// Whether MIDIMON or LOOM-8 has to go on first and couldn't be had.
    var isMissingFirstStep: Bool {
        switching.needsFirstStep && switching.firstStep == nil
    }

    /// Whether these steps move the FM-1 to a different firmware, which can erase its projects
    /// and samples: always for a chain, or for V15 over a firmware that reports V15, otherwise as
    /// the check found.
    var isSwitching: Bool {
        steps.count > 1 || checked == .found(.switchingFirmware) || reinstallsOfficial
    }

    /// Whether the FM-1 already reports the identity this custom firmware has: a reinstall, or
    /// another release of the same firmware.
    var isSameIdentity: Bool {
        !isSwitching && checked == .found(.sameIdentity)
    }

    /// Whether the FM-1 reports the official firmware this is, which it may not be running:
    /// TransitFM1 reports V15.
    var canReinstallOfficial: Bool {
        checked == .found(.reinstall) && steps.count == 1 && identity?.isOfficial == true
    }

    /// Whether the guide saved with the last install says the FM-1 isn't really running the
    /// official firmware it reports.
    var knowsItIsntOfficial: Bool {
        canReinstallOfficial && switching.running.map(SwitchingGuide.reportsOfficialIdentity) == true
    }

    /// Whether this installs the official firmware over one that reports it, as the saved guide
    /// says it isn't really running it.
    var reinstallsOfficial: Bool { knowsItIsntOfficial }

    /// Whether the FM-1 is already running exactly this, so there's nothing to install, unless
    /// the person says it's a firmware that reports the official one's identity.
    var isAlreadyInstalled: Bool {
        checked == .found(.reinstall) && steps.count == 1 && !knowsItIsntOfficial
    }

    /// Whether the install can start, once the person has (or hasn't) confirmed a switch,
    /// accepted an untested firmware, and said the FM-1 isn't really running the official
    /// firmware it reports.
    func canStart(confirmsSwitch: Bool, acceptsUntested: Bool, confirmsNotOfficial: Bool = false) -> Bool {
        guard identity != nil, switching.isRead, !isMissingOfficial, !isMissingFirstStep,
            !isUntested || acceptsUntested, !needsStartUp
        else { return false }
        switch checked {
        case .checking, .failed:
            return false
        case .finishingUpdate:
            return true
        case .found:
            let confirmsReinstall = canReinstallOfficial && confirmsNotOfficial
            let isSwitch = isSwitching || confirmsReinstall
            return (!isAlreadyInstalled || confirmsReinstall) && (!isSwitch || confirmsSwitch)
        }
    }

    /// Asks the connected FM-1 what installing `first` would do.
    @MainActor
    static func check(_ first: StoredFirmware?, on device: DeviceController) async -> InstallCheckState {
        guard let first, let identity = device.identity else { return .checking }
        guard !identity.isLoader else { return .finishingUpdate }
        do {
            return .found(try await device.check(first).kind)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
