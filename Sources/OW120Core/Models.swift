import Foundation

public enum OWError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct Layout: Sendable {
    public let root: URL
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OW120")) { self.root = root }
    private var runtimeID: String { (try? String(contentsOf: root.appendingPathComponent("active-runtime"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "crossover" }
    public var isSoju: Bool { runtimeID == "community-soju26" }
    public var isCommunity: Bool { isSoju || runtimeID == "community-cx24" }
    public var community: URL { root.appendingPathComponent("Community") }
    public var runtimeName: String { isSoju ? "社区 Wine 11 · 免费运行时" : isCommunity ? "社区 WineCX 24 · 免费运行时" : "CrossOver · 独立运行时" }
    public var runtime: URL { isCommunity ? community.appendingPathComponent(isSoju ? "soju26" : "cx24/wswine.bundle") : root.appendingPathComponent("Runtime/CrossOver.app") }
    public func wineArguments(_ args: [String]) -> [String] { isCommunity ? args : ["--bottle", "ow120", "--no-gui", "--cx-app"] + args }
    public var engine: URL { isCommunity ? runtime : runtime.appendingPathComponent("Contents/SharedSupport/CrossOver") }
    public var bottles: URL { root.appendingPathComponent("Bottles") }
    public var bottle: URL { isCommunity ? community.appendingPathComponent(isSoju ? "prefix-soju26" : "prefix") : bottles.appendingPathComponent("ow120") }
    public var documents: URL { isCommunity ? community.appendingPathComponent(isSoju ? "Documents-soju26" : "Documents") : root.appendingPathComponent("Documents") }
    public var settings: URL { documents.appendingPathComponent("Overwatch/Settings/Settings_v0.ini") }
    public var sessions: URL { (isCommunity ? community : root).appendingPathComponent("Sessions") }
    public var manifest: URL { root.appendingPathComponent("installation.json") }
    public var profileFile: URL { (isCommunity ? community : root).appendingPathComponent("profile.json") }
    public var launchProfileFile: URL { root.appendingPathComponent("launch-profile.json") }
    public var dxmtConfig: URL { (isCommunity ? community : root).appendingPathComponent("dxmt.conf") }
    public var cache: URL { (isCommunity ? community : root).appendingPathComponent("ShaderCache/dxmt-0.80-ow2-0.2") }
    public var isPrepared: Bool { FileManager.default.fileExists(atPath: manifest.path) && FileManager.default.fileExists(atPath: engine.appendingPathComponent("bin/wine").path) && FileManager.default.fileExists(atPath: bottle.appendingPathComponent("cxbottle.conf").path) }
}

public enum RenderBackend: String, Codable, CaseIterable, Sendable {
    case dxmt, d3dmetal
    public var title: String { self == .dxmt ? "DXMT · 低卡顿" : "D3DMetal · 对照" }
}

public struct GameProfile: Codable, Equatable, Sendable {
    public var width: Int = 1600
    public var height: Int = 1000
    public var targetFPS: Int = 120
    public var backend: RenderBackend = .dxmt
    public var msync: Bool = true
    /// Keep parsed IR in RAM. True saves memory on 16 GB machines but rematerializes shaders in fights.
    public var releaseShaderIR: Bool = false
    public var showHUD: Bool = false
    public var borderless: Bool = true
    public var disableRetina: Bool = true
    public var videoMemoryMB: Int = 10240
    /// Missing in older profiles. Keep the existing Metal pacing by default.
    public var metalFramePacing: Bool? = nil
    public var usesMetalFramePacing: Bool { metalFramePacing ?? true }
    /// Output size and 3D rendering size are independent. Old profiles keep 100%.
    public var renderScalePercent: Int? = nil
    /// Older saved settings remain manual; only an explicit preset enables
    /// device matching at the next launch.
    public var configurationMode: ConfigurationMode? = nil
    public var selectedConfigurationMode: ConfigurationMode { configurationMode ?? .manual }
    public var effectiveRenderScale: Int { renderScalePercent ?? 100 }
    public var graphicsAPI: String { backend == .dxmt ? "Dx11" : "Dx12" }
    public init() {}
    public static var balanced: GameProfile { var p = GameProfile(); p.width = 1920; p.height = 1200; return p }
    public static func competitive(memoryGB: Int) -> GameProfile {
        var profile = GameProfile()
        if memoryGB < 24 {
            profile.releaseShaderIR = true
            profile.videoMemoryMB = 6144
        }
        return profile
    }
    /// Conservative starting point for a new Mac; never overrides an existing
    /// saved profile. Desktop fitting happens separately at launch.
    public static func recommended(memoryGB: Int, chip: String) -> GameProfile {
        var result = competitive(memoryGB: memoryGB)
        let largerGPU = chip.localizedCaseInsensitiveContains("Pro") || chip.localizedCaseInsensitiveContains("Max") || chip.localizedCaseInsensitiveContains("Ultra")
        result.renderScalePercent = memoryGB <= 16 ? 75 : largerGPU ? 100 : 80
        result.configurationMode = .automatic
        return result
    }
    /// Wine with Retina disabled reports desktop points as Windows pixels.
    /// Borderless output must use that same coordinate space, including on
    /// notched displays; a fixed 16:10 size can exceed the desktop bounds.
    public func fittingDesktop(width: Int, height: Int) -> GameProfile {
        guard borderless, disableRetina, (640...8192).contains(width), (480...8192).contains(height) else { return self }
        var result = self
        result.width = width; result.height = height
        return result
    }
    /// Fixed output uses a Retina-aware window. Borderless uses desktop points;
    /// enlarging only its swapchain can put the pointer and clicks out of sync.
    public func withFixedOutput(width: Int, height: Int) -> GameProfile {
        var result = self
        result.width = width; result.height = height
        result.borderless = false; result.disableRetina = false
        return result
    }
    public func displayRegistry(_ original: String, community: Bool) -> String {
        var text = original
        if disableRetina {
            if community {
                text = text.replacingOccurrences(of: #""LogPixels"=dword:[0-9a-fA-F]{8}"#, with: #""LogPixels"=dword:00000060"#, options: .regularExpression)
            }
        }
        // Wine 11 deliberately reads global RetinaMode, ignoring AppDefaults so
        // monitor coordinates stay consistent across processes in one prefix.
        text = WineReg.set(text, section: "Software\\\\Wine\\\\Mac Driver", values: ["RetinaMode": disableRetina ? "n" : "y"])
        return WineReg.set(text, section: "Software\\\\Wine\\\\AppDefaults\\\\Overwatch.exe\\\\Mac Driver", values: ["RetinaMode": disableRetina ? "n" : "y"])
    }
    public func validate() throws {
        guard [120, 144, 165, 240].contains(targetFPS), (640...8192).contains(width), (480...8192).contains(height) else { throw OWError.message("配置超出支持范围。帧率最低为 120 FPS。") }
        guard videoMemoryMB == 0 || (videoMemoryMB >= 4096 && videoMemoryMB <= 24576) else { throw OWError.message("显存上报值超出范围。") }
        guard (50...100).contains(effectiveRenderScale) else { throw OWError.message("渲染比例支持 50% 到 100%，不会改变输出分辨率。") }
    }
    public var gameOverrides: [String: String] {
        [
            "GraphicsAPI": graphicsAPI, "FrameRateCap": "\(targetFPS)",
            "UseCustomFrameRates": "1", "MaxFramesPerSecond": "\(targetFPS)",
            "DesiredFrameRate": "\(targetFPS)",
            "FullScreenWidth": "\(width)", "FullScreenHeight": "\(height)", "FullScreenRefresh": "120",
            "WindowedWidth": "\(width)", "WindowedHeight": "\(height)",
            "WindowedPosX": "0", "WindowedPosY": "0",
            "WindowMode": borderless ? "2" : "1",
            "FullscreenWindow": borderless ? "1" : "0",
            "FullscreenWindowEnabled": borderless ? "1" : "0",
            "GFXPresetLevel": "1", "LimitToRefresh": "0", "LimitTo30": "0",
            "VSyncEnabled": "0", "VerticalSyncEnabled": "0", "TripleBufferingEnabled": "0", "ShowFPSCounter": "1",
            // RenderScale is a legacy level, not a percentage. Custom world
            // scale uses percentage-valued bounds; never write RenderScale=80/100.
            "UseGPUScale": "0", "RenderScale": "0", "DynamicRenderScale": "0",
            "UseCustomWorldScale": "1", "MinWorldScale": "\(effectiveRenderScale).000000",
            "MaxWorldScale": "\(effectiveRenderScale).000000",
            "DirectionalShadowDetail": "0", "EffectsQuality": "0", "DynamicAmbient": "0",
            "LocalFogDetail": "0", "LocalReflections": "0", "ModelQuality": "0", "RefractionDetail": "0",
            "AADetail": "0", "LightQuality": "0", "TextureQuality": "0", "PhysicsQuality": "0",
            "MaxAnisotropy": "1", "AmbientOcclusionDetail": "0", "ShaderQuality": "0"
        ]
    }
    public var dxmtText: String {
        """
        # OW120 competitive profile. 120 FPS is the target, not a measured result.
        d3d11.preferredMaxFrameRate = \(usesMetalFramePacing ? targetFPS : 0)
        d3d11.releaseShaderIR = \(releaseShaderIR ? "True" : "False")
        dxgi.forceSDR = True
        dxgi.handleAltTab = True
        dxgi.customVideoMemory = \(videoMemoryMB)
        dxmt.shaderMetalVersion = 320
        # No spatial output upscale: preserve GPU time for high refresh gameplay.

        """
    }
}

public struct Installation: Codable, Sendable {
    public var version: Int = 1
    public var sourceApp: String
    public var sourceBottle: String
    public var crossoverVersion: String
    public var createdAt: Date
    public var patchSHA256: String
    public var sourceFingerprint: [String: String]
}

public struct MachineInfo: Codable, Sendable {
    public var chip: String
    public var memoryGB: Int
    public var macOS: String
    public var crossoverVersion: String
    public var sourceBottle: String?
    public var displayHz: Double
    public var maximumDisplayHz: Double
    public var lowPowerMode: Bool
    public var prepared: Bool
    public var desktopWidth: Int? = nil
    public var desktopHeight: Int? = nil
}

public struct SessionInfo: Codable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var profile: GameProfile
    public var gamePID: Int32?
    public var benchmarkStartFrame: Int?
    public var benchmarkEndFrame: Int?
    public var benchmarkStartedAt: Date?
    public var benchmarkEndedAt: Date?
    public var folder: URL
    public init(profile: GameProfile, folder: URL) {
        id = folder.lastPathComponent; startedAt = Date(); self.profile = profile; self.folder = folder
    }
}

public enum JSONFile {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T { try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
