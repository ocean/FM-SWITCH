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
        fileName.lowercased().split { "-_. ".contains($0) }.contains { word in
            word.hasPrefix("smk") || words.contains(String(word))
        }
    }
}

extension CatalogueEntry {
    /// The entry without builds for other devices, for lists built before they were left out.
    ///
    /// One that pointed at such a build points at an FM-1 build instead.
    func onlyForTheFM1() -> CatalogueEntry {
        guard let builds else { return self }
        let kept = builds.filter { !OtherDevices.isPackage($0.url.lastPathComponent) }
        guard kept.count != builds.count else { return self }
        var entry = self
        if let url = packageURL, OtherDevices.isPackage(url.lastPathComponent), let first = kept.first {
            entry.packageURL = first.url
            entry.size = first.size
            entry.sha256 = first.sha256
        }
        entry.builds = kept.count > 1 ? kept : nil
        return entry
    }
}
