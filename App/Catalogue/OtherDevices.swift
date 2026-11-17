/// Packages for M-VAVE's other devices, such as the SMK-37, that some releases carry.
///
/// FM-SWITCH only installs on the FM-1, so they're left out.
public enum OtherDevices {
    /// Words in a package's file name that mark it for another device, as in
    /// `kayak-1.3-smk37-elite.fwsc`; any word starting "smk" counts too.
    static let words: Set<String> = ["mke", "elite"]

    /// Whether `text`, a device's identity or USB name, names an SMK-37.
    ///
    /// fm1-base, which SMK-37 builds are made with, and M-VAVE's own firmware name its models
    /// "SMK-37 Pro", "SMK-37 Elite" and "MKE-P37" (the same hardware), as in `SMK-37 Elite_016`
    /// and its loader's `ota-MKE-P37_900`, and its USB port ends in "SMK-37" or is "MKE-P37".
    public static func isNamed(_ text: String) -> Bool {
        let text = text.lowercased()
        return text.contains("smk") || text.contains("mke")
    }

    /// Whether `fileName` is a package for another device.
    static func isPackage(_ fileName: String) -> Bool {
        fileWords(fileName).contains { word in
            word.hasPrefix("smk") || words.contains(word)
        }
    }

    /// The builds in `builds` for the FM-1, by what sets them apart.
    ///
    /// Where one is named "fm1", the others are for another device: Erik37's `erik37-fm1.fwsc` is
    /// for the FM-1, and its plain `erik37.fwsc` for the SMK-37 Pro.
    static func forTheFM1(_ builds: [CatalogueEntry.Build]) -> [CatalogueEntry.Build] {
        let kept = builds.filter { !isPackage($0.url.lastPathComponent) }
        let marked = kept.filter { fileWords($0.name).contains("fm1") }
        return kept.contains { $0.name.lowercased() == "fm1" } ? marked : kept
    }

    /// The words in a file name, with "fm-1" and "fm_1" as one word.
    private static func fileWords(_ fileName: String) -> [String] {
        fileName.lowercased()
            .replacingOccurrences(of: "fm-1", with: "fm1")
            .replacingOccurrences(of: "fm_1", with: "fm1")
            .split { "-_. ".contains($0) }
            .map(String.init)
    }
}

extension CatalogueEntry {
    /// The entry without builds for other devices, for lists built before they were left out.
    ///
    /// One that pointed at such a build points at an FM-1 build instead.
    func onlyForTheFM1() -> CatalogueEntry {
        guard let builds else { return self }
        let kept = OtherDevices.forTheFM1(builds)
        guard kept.count != builds.count else { return self }
        var entry = self
        if let url = packageURL, !kept.contains(where: { $0.url == url }), let first = kept.first {
            entry.packageURL = first.url
            entry.size = first.size
            entry.sha256 = first.sha256
        }
        entry.builds = kept.count > 1 ? kept : nil
        return entry
    }
}
