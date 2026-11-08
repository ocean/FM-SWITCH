import FM1Kit
import Foundation

/// How to switch the FM-1 away from each firmware, from FM1Kit's guides (`LeavingGuide`).
///
/// A guide is saved with each install from this app (``FlashRecord/guide``), so the app knows
/// which bootloader the FM-1 has and what it's really running, even when the firmware reports
/// another's identity, as TransitFM1 reports V15's. Without one, the bootloader is the one the
/// person says starts their FM-1.
enum SwitchingGuide {
    /// The guide to what an FM-1 reporting `identity` is running.
    ///
    /// - Parameters:
    ///   - identity: What the FM-1 reports.
    ///   - saved: The guide saved with the last install from this app.
    ///   - startUp: What the person says starts their FM-1, for a bootloader the guide doesn't know.
    /// - Returns: The guide, or `nil` for a firmware nothing is known about, or while the FM-1 is
    ///   waiting in its update loader.
    static func running(_ identity: FM1Identity?, saved: LeavingGuide?, startUp: StartUp?) -> LeavingGuide? {
        guard let identity, !identity.isLoader else { return nil }
        if let saved, saved.identity == identity {
            return filling(saved, from: startUp)
        }
        let name: String
        let bootArea: FM1BootArea
        if identity == .officialV15 {
            (name, bootArea) = ("V15", .v15)
        } else if identity == .officialV16 {
            (name, bootArea) = ("V16", .v16)
        } else if identity.isOpenFirmware {
            (name, bootArea) = ("M-VAVE's open firmware", .openFirmware)
        } else {
            return nil
        }
        // M-VAVE's firmwares bring their own bootloader, unless they went on in download mode,
        // which keeps the one there.
        return LeavingGuide(
            firmwareName: name,
            identity: identity,
            updateCode: .mVave,
            bootArea: startUp == .mBootloader ? .mBootloader : bootArea
        )
    }

    /// The guide to `package` once it's installed over the firmware `previous` describes.
    ///
    /// - Returns: The guide, or `nil` for a package that isn't a firmware.
    static func guide(
        installing package: FwscPackage,
        named name: String,
        over previous: LeavingGuide?,
        startUp: StartUp?
    ) -> LeavingGuide? {
        LeavingGuide(
            package: package,
            name: name,
            bootArea: previous?.bootArea ?? startUp?.bootArea,
            installedBy: previous?.updateCode
        )
    }

    /// What installing `package` over the firmware `previous` describes leaves: the guide to it,
    /// and what starts the FM-1 now, when the install brought a bootloader other than the one
    /// it had.
    static func installing(
        _ package: FwscPackage,
        named name: String,
        over previous: LeavingGuide?,
        startUp: StartUp?
    ) -> (guide: LeavingGuide?, startUp: StartUp?) {
        let guide = guide(installing: package, named: name, over: previous, startUp: startUp)
        guard let bootArea = guide?.bootArea, bootArea != previous?.bootArea ?? startUp?.bootArea else {
            return (guide, nil)
        }
        return (guide, StartUp(bootArea))
    }

    /// `guide`, with the bootloader the person says their FM-1 has when the guide doesn't know.
    static func filling(_ guide: LeavingGuide, from startUp: StartUp?) -> LeavingGuide {
        guard guide.bootArea == nil, let bootArea = startUp?.bootArea else { return guide }
        return LeavingGuide(
            firmwareName: guide.firmwareName,
            identity: guide.identity,
            updateCode: guide.updateCode,
            bootArea: bootArea
        )
    }

    /// Whether what a guide says depends on the bootloader: firmwares with Felucca's original
    /// check take M-VAVE's firmwares only onto the bootloader they bring.
    static func dependsOnBootArea(_ updateCode: UpdateCode) -> Bool {
        updateCode == .feluccaOriginalCheck || updateCode == .recognisesV15
    }

    /// True when the firmware a guide describes reports the official firmware's identity without
    /// being it, as TransitFM1 does.
    static func reportsOfficialIdentity(_ guide: LeavingGuide) -> Bool {
        guide.identity.isOfficial && guide.updateCode != .mVave
    }
}

extension LeavingDestination {
    /// Where installing `package` takes the FM-1.
    init(installing package: FwscPackage) {
        switch OfficialFirmware.matching(package)?.identity {
        case .officialV15?: self = .v15
        case .officialV16?: self = .v16
        default:
            if package.identity.isOpenFirmware {
                self = .openFirmware
            } else {
                self = package.isFirmware ? .feluccaPlatform : .mBootloader
            }
        }
    }
}

extension StartUp {
    /// The bootloader this start-up is, or `nil` when the person isn't sure.
    var bootArea: FM1BootArea? {
        switch self {
        case .mVave: .v15
        case .v16: .v16
        case .mBootloader: .mBootloader
        case .openFirmware: .openFirmware
        case .notSure: nil
        }
    }

    /// The start-up a bootloader is.
    init(_ bootArea: FM1BootArea) {
        switch bootArea {
        case .v15: self = .mVave
        case .v16: self = .v16
        case .mBootloader: self = .mBootloader
        case .openFirmware: self = .openFirmware
        }
    }
}

/// The firmwares with Felucca's fixed update check that go on first when the firmware on the FM-1
/// can't install the one picked: they install any firmware, and every firmware takes them.
enum FixedFirmware {
    /// MIDIMON's catalogue ID, the one downloaded when none is saved.
    static let midimon = "midimon"
    /// The ones FM1Kit has tried on an FM-1, by catalogue ID: MIDIMON and LOOM-8.
    static let catalogueIDs = [midimon, "loom"]

    enum Failure: LocalizedError {
        case notListed
        case notFixed(String)

        var errorDescription: String? {
            switch self {
            case .notListed: "MIDIMON isn't in the firmware list right now, so it can't be downloaded."
            case .notFixed(let name): "The \(name) saved doesn't have the update check that installs any firmware."
            }
        }
    }

    /// A saved MIDIMON or LOOM-8 with the fixed check, or MIDIMON downloaded from the list.
    @MainActor
    static func find(in library: FirmwareLibrary, catalogue: CatalogueStore) async throws -> StoredFirmware {
        for id in catalogueIDs {
            for item in library.items where item.catalogueID == id {
                if (try? await library.loadPackage(item).updateCode) == .feluccaFixedCheck { return item }
            }
        }
        guard let entry = catalogue.entry(id: midimon) else { throw Failure.notListed }
        let item = try await library.download(entry)
        guard try await library.loadPackage(item).updateCode == .feluccaFixedCheck else {
            throw Failure.notFixed(item.name)
        }
        return item
    }
}

extension FixedFirmware {
    /// Carries on with the install that was refused, with MIDIMON or LOOM-8 on first, or when the
    /// person didn't confirm switching firmware for it, opens MIDIMON's page to install it from.
    @MainActor
    static func installFirst(model: AppModel) async throws {
        guard model.device.job?.confirmsSwitchingFirmware == true else {
            model.device.dismissFlash()
            model.requestedPage = .firmware(midimon)
            return
        }
        model.device.installFirst(try await find(in: model.library, catalogue: model.catalogue))
    }
}
