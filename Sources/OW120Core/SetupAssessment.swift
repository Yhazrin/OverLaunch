import Foundation

public struct SetupDeviceReport: Sendable {
    public let supported: Bool
    public let rosettaReady: Bool
    public let availableGB: Int?
    public var canProceed: Bool { supported && rosettaReady }
}

public struct ImportAssessment: Sendable {
    public let source: URL?
    public let issue: String?
    public var canProceed: Bool { source != nil && issue == nil }

    /// Read-only validation before any downloads or changes to the private prefix.
    public static func inspect(_ selection: URL?, destination: URL) -> ImportAssessment {
        guard var source = selection else { return ImportAssessment(source: nil, issue: "请选择已有游戏容器。") }
        if source.lastPathComponent == "drive_c" { source.deleteLastPathComponent() }
        source = source.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        for (path, label) in [
            ("drive_c/Program Files (x86)/Battle.net/Battle.net.exe", "国服战网"),
            ("drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe", "守望先锋")
        ] {
            let file = source.appendingPathComponent(path)
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: file.path, isDirectory: &directory), !directory.boolValue else {
                return ImportAssessment(source: source, issue: "未找到\(label)。请选择包含 drive_c 的完整游戏容器。")
            }
            guard file.resolvingSymlinksInPath().pathComponents.starts(with: source.pathComponents) else {
                return ImportAssessment(source: source, issue: "\(label)位于容器之外。请先将完整游戏安装放入容器，再导入。")
            }
        }
        let keys: Set<URLResourceKey> = [.volumeSupportsFileCloningKey, .volumeUUIDStringKey]
        let sourceVolume = try? source.resourceValues(forKeys: keys)
        let targetVolume = try? existingAncestor(destination).resourceValues(forKeys: keys)
        if sourceVolume?.volumeSupportsFileCloning == false || targetVolume?.volumeSupportsFileCloning == false {
            return ImportAssessment(source: source, issue: "导入需要支持写时复制的 APFS 磁盘。请先将容器移到本机 APFS 磁盘。")
        }
        if let first = sourceVolume?.volumeUUIDString, let second = targetVolume?.volumeUUIDString, first != second {
            return ImportAssessment(source: source, issue: "游戏容器与应用数据不在同一磁盘卷。请将容器移到用户目录所在的 APFS 卷后导入。")
        }
        return ImportAssessment(source: source, issue: nil)
    }
}

private func existingAncestor(_ location: URL) -> URL {
    var result = location
    while !FileManager.default.fileExists(atPath: result.path), result.path != "/" { result.deleteLastPathComponent() }
    return result
}

extension EnvironmentService {
    public func setupDeviceReport() -> SetupDeviceReport {
        let silicon = ((try? Command.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        let translated = (try? Command.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])) != nil
        let values = try? existingAncestor(layout.root).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return SetupDeviceReport(supported: silicon && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14,
                                 rosettaReady: translated,
                                 availableGB: values?.volumeAvailableCapacityForImportantUsage.map { Int($0 / 1_073_741_824) })
    }
}
