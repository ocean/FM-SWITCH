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

/// Whether installing a firmware can start, and what the person has to confirm first: the rules
/// both looks' confirmation screens share.
struct InstallReadiness: Equatable {
    /// What will be installed, in order: the official firmware first when it's needed.
    var steps: [StoredFirmware]
    var checked: InstallCheckState
    var identity: FM1Identity?
    /// Whether the official firmware has to go on first, and there's no copy of it.
    var isMissingOfficial: Bool
    /// Whether the firmware is from the list but hasn't been tested on a real FM-1, so the person
    /// has to accept that first.
    var isUntested: Bool
    /// Whether the firmware is built on Felucca's update code, so what's possible afterwards from
    /// an iPhone depends on the FM-1's start-up.
    var hasFeluccaUpdateCode: Bool
    /// What the person says starts their FM-1, or nil until they've been asked.
    var startUp: StartUp?
    /// The warning that getting back to M-VAVE's firmwares will take a Mac, when it applies.
    var macWarning: FeluccaUpdateCode.Warning?

    /// Why an untested firmware is a risk, for both looks' confirmation screens.
    static let untestedWarning = """
        This firmware is only listed on the FM1 Resource Hub, not on FM-1 Firmware Hub or \
        fm1-editor.com, so it may not have been well tested on a real FM-1. It may not install, or \
        may not let another firmware install after it. Recovery might need a computer, check \
        this app's settings for further information.
        """

    @MainActor
    init(
        target: StoredFirmware,
        requiresOfficial: Bool,
        checked: InstallCheckState,
        usesFeluccaUpdateCode: Bool,
        model: AppModel
    ) {
        let viaOfficial = requiresOfficial || model.settings.alwaysViaOfficial
        steps = model.device.plan(
            for: target, requiresOfficial: requiresOfficial, alwaysViaOfficial: model.settings.alwaysViaOfficial)
        self.checked = checked
        identity = model.device.identity
        isMissingOfficial = viaOfficial && target.source != .official && model.library.official == nil
        let listed = target.catalogueID.flatMap(model.catalogue.listedEntry(id:))
        isUntested = target.source == .catalogue && listed?.isHardwareTested == false
        hasFeluccaUpdateCode = usesFeluccaUpdateCode
        startUp = model.settings.startUp
        if hasFeluccaUpdateCode, let startUp, startUp != .mVave {
            macWarning = FeluccaUpdateCode.Warning(installing: target.catalogueID, named: target.name, startUp: startUp)
        }
    }

    /// Whether the person has to say what starts their FM-1 before this can install.
    var needsStartUp: Bool {
        hasFeluccaUpdateCode && startUp == nil
    }

    /// Whether these steps move the FM-1 to a different firmware, which can erase its projects
    /// and samples: always for a chain through the official firmware, otherwise as the check
    /// found.
    var isSwitching: Bool {
        steps.count > 1 || checked == .found(.switchingFirmware)
    }

    /// Whether the FM-1 already reports the identity this custom firmware has: a reinstall, or
    /// another release of the same firmware.
    var isSameIdentity: Bool {
        !isSwitching && checked == .found(.sameIdentity)
    }

    /// Whether the FM-1 is already running exactly this, so there's nothing to install.
    var isAlreadyInstalled: Bool {
        checked == .found(.reinstall) && steps.count == 1
    }

    /// Whether the install can start, once the person has (or hasn't) confirmed a switch, and
    /// accepted an untested firmware.
    func canStart(confirmsSwitch: Bool, acceptsUntested: Bool) -> Bool {
        guard identity != nil, !isMissingOfficial, !isUntested || acceptsUntested, !needsStartUp else { return false }
        switch checked {
        case .checking, .failed:
            return false
        case .finishingUpdate:
            return true
        case .found:
            return !isAlreadyInstalled && (!isSwitching || confirmsSwitch)
        }
    }

    /// Whether `target` is built on Felucca's update code, read from its package, or for one that
    /// can't be read, from ``FeluccaUpdateCode/known``.
    @MainActor
    static func usesFeluccaUpdateCode(_ target: StoredFirmware, in library: FirmwareLibrary) async -> Bool {
        do {
            return try await library.loadPackage(target).usesFeluccaUpdateCode
        } catch {
            return FeluccaUpdateCode.isKnown(target.catalogueID)
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
