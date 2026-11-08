import FM1Kit

extension OfficialFirmware {
    /// M-VAVE's official firmware `package` is, V15 or V16, by its hash.
    static func official(_ package: FwscPackage) -> Self? {
        matching(package).flatMap { official.contains($0) ? $0 : nil }
    }
}
