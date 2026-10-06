import Foundation

public struct HeroIcon: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var englishName: String
    public var sha256: String
}

public struct HeroIconCatalog: Codable, Sendable {
    public var sourceURL: String
    public var sourceRevision: String
    public var heroes: [HeroIcon]

    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        var seen = Set<String>()
        guard !heroes.isEmpty, heroes.allSatisfy({
            $0.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil &&
            seen.insert($0.id).inserted && !$0.title.isEmpty &&
            $0.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        }) else { throw OWError.message("英雄图标资源目录无效。") }
    }
    public func contains(_ id: String) -> Bool { id == "default" || heroes.contains { $0.id == id } }
}

public struct LauncherAppearance: Codable, Equatable, Sendable {
    public var iconID: String = "default"
    public init(iconID: String = "default") { self.iconID = iconID }
}

/// Appearance never writes game preferences or a signed bundle's contents.
public struct AppearanceStore: Sendable {
    public let file: URL
    public init(root: URL) { file = root.appendingPathComponent("launcher-appearance.json") }
    public func load(catalog: HeroIconCatalog) -> LauncherAppearance {
        guard let value = try? JSONDecoder().decode(LauncherAppearance.self, from: Data(contentsOf: file)), catalog.contains(value.iconID) else { return LauncherAppearance() }
        return value
    }
    public func save(_ value: LauncherAppearance, catalog: HeroIconCatalog) throws {
        guard catalog.contains(value.iconID) else { throw OWError.message("所选英雄图标不存在，请重新选择。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
    }
}
