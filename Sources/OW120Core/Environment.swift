import Foundation
import CoreGraphics
import Darwin

private final class OperationLock {
    let descriptor: Int32
    init(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        descriptor = open(root.appendingPathComponent(".operation.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw OWError.message("无法创建运行锁。") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw OWError.message("另一个操作正在进行，请稍后重试。") }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public actor EnvironmentService {
    public let layout: Layout
    private let fm = FileManager.default
    private var children: [Process] = []
    public static let patchHash = "8d4e778ff9868883a064d7b9bfb372ed6e286e4233f60c053075ca983b2bc256"
    public init(layout: Layout = Layout()) { self.layout = layout }

    public func detectBottle() -> URL? {
        let home = fm.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        let all = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return all.sorted { $0.lastPathComponent < $1.lastPathComponent }.first { fm.fileExists(atPath: gameExecutable(in: $0).path) }
    }
    public func gameExecutable(in bottle: URL) -> URL { bottle.appendingPathComponent("drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe") }
    public func inspect() -> MachineInfo {
        let chip = (try? Command.run("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "Apple Silicon"
        let mem = Int((try? Command.run("/usr/sbin/sysctl", ["-n", "hw.memsize"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "0") ?? 0
        let display = CGMainDisplayID()
        let currentHz = CGDisplayCopyDisplayMode(display)?.refreshRate ?? 0
        let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
        let desktop = CGDisplayCopyDisplayMode(display)
        return MachineInfo(chip: chip, memoryGB: mem / 1_073_741_824, macOS: ProcessInfo.processInfo.operatingSystemVersionString, crossoverVersion: appVersion(URL(fileURLWithPath: "/Applications/CrossOver.app")), sourceBottle: detectBottle()?.path, displayHz: currentHz, maximumDisplayHz: modes.map(\.refreshRate).max() ?? 0, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, prepared: layout.isPrepared, desktopWidth: desktop?.width, desktopHeight: desktop?.height)
    }
    private func appVersion(_ app: URL) -> String {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return "未安装" }
        return dict["CFBundleShortVersionString"] as? String ?? "未知"
    }
    private func displayFitted(_ profile: GameProfile) -> GameProfile {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { return profile }
        return profile.fittingDesktop(width: mode.width, height: mode.height)
    }
    public func profile() -> GameProfile {
        if let saved = try? JSONFile.read(GameProfile.self, from: layout.profileFile) { return displayFitted(saved) }
        let machine = inspect()
        return LaunchConfiguration.match(.automatic, machine: machine, current: GameProfile())
    }
    public func launchProfile() -> GameProfile {
        displayFitted((try? JSONFile.read(GameProfile.self, from: layout.launchProfileFile)) ?? profile())
    }
    /// Queue launcher preferences without touching a live game, registry or DXMT.
    public func saveLaunchProfile(_ profile: GameProfile) throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try profile.validate()
        guard !layout.isCommunity || profile.backend == .dxmt else { throw OWError.message("免费运行环境当前使用 DXMT。") }
        try JSONFile.write(resolveForLaunch(profile), to: layout.launchProfileFile)
    }
    private func resolveForLaunch(_ profile: GameProfile) -> GameProfile {
        guard profile.selectedConfigurationMode != .manual else { return displayFitted(profile) }
        return LaunchConfiguration.match(profile.selectedConfigurationMode, machine: inspect(), current: profile)
    }
    public func active() -> Bool {
        let listing = (try? Command.run("/bin/ps", ["-axo", "comm="])) ?? ""
        return listing.split(separator: "\n").contains { $0.contains(layout.runtime.path) }
    }
    private func requireStopped() throws {
        if active() { throw OWError.message("请先从战网菜单退出，并关闭游戏，再修改配置或运行环境。") }
    }
    private func fingerprint(_ bottle: URL, app: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for relative in ["cxbottle.conf", "user.reg", "system.reg"] {
            let file = bottle.appendingPathComponent(relative)
            if fm.fileExists(atPath: file.path) { result["bottle/" + relative] = try Command.sha256(file) }
        }
        let file = app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/dxmt/x86_64-windows/d3d11.dll")
        result["runtime/d3d11.dll"] = try Command.sha256(file)
        return result
    }
    public func verifyOriginal() throws -> Bool {
        let manifest = try JSONFile.read(Installation.self, from: layout.manifest)
        if manifest.version >= 2 { return try CommunityInstaller.sourceFingerprint(URL(fileURLWithPath: manifest.sourceBottle)) == manifest.sourceFingerprint }
        return try fingerprint(URL(fileURLWithPath: manifest.sourceBottle), app: URL(fileURLWithPath: manifest.sourceApp)) == manifest.sourceFingerprint
    }

    /// Verify without executing code, so damaged local bundles cannot trigger a
    /// Gatekeeper “move to Trash” dialog during launch or telemetry discovery.
    public func verifyRuntime() throws {
        if layout.isCommunity {
            for file in [layout.engine.appendingPathComponent("bin/wine"), layout.engine.appendingPathComponent("bin/wineserver"), layout.community.appendingPathComponent("graphics/dxmt-ow2-pack/x86_64-unix/winemetal.so")] {
                try Command.run("/usr/bin/codesign", ["--verify", "--strict", file.path])
            }
            return
        }
        guard fm.fileExists(atPath: layout.runtime.path) else { throw OWError.message("独立运行时缺失，请点“修复运行时”；已有游戏无需重新下载。") }
        do { try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", layout.runtime.path]) }
        catch { throw OWError.message("独立运行时签名校验失败，已阻止启动。请点“修复运行时”；原版 CrossOver 不受影响。\n\(error.localizedDescription)") }
    }

    private func patchAndSign(_ app: URL, archive: URL, staging: URL) throws {
        guard try Command.sha256(archive) == Self.patchHash else { throw OWError.message("图形组件校验失败。") }
        let assets = staging.appendingPathComponent("patch")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        let members = try Command.run("/usr/bin/tar", ["-tzf", archive.path])
        guard members.split(separator: "\n").allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else { throw OWError.message("图形组件归档路径无效。") }
        try Command.run("/usr/bin/tar", ["-xzf", archive.path, "-C", assets.path])
        let patch = assets.appendingPathComponent("dxmt-ow2-pack")
        let libraries = app.appendingPathComponent("Contents/SharedSupport/CrossOver/lib/dxmt")
        for subdir in ["i386-windows", "x86_64-windows", "x86_64-unix"] {
            for file in try fm.contentsOfDirectory(at: patch.appendingPathComponent(subdir), includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard !(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false) else { throw OWError.message("组件含有意外的符号链接。") }
                let destination = libraries.appendingPathComponent(subdir).appendingPathComponent(file.lastPathComponent)
                guard destination.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(app.path + "/") else { throw OWError.message("组件目标目录未隔离。") }
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: file, to: destination)
            }
        }
        // Sign only our changed native library, then the outer resource seal.
        // Preserve existing app entitlements; do not force-resign vendor helpers.
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", libraries.appendingPathComponent("x86_64-unix/winemetal.so").path])
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", "--preserve-metadata=entitlements,flags", "--generate-entitlement-der", app.path])
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    /// Recover a deleted or damaged runtime without cloning the game again.
    public func repairRuntime(archive: URL, progress: @Sendable (String) -> Void = { _ in }) throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped()
        guard !layout.isCommunity else { throw OWError.message("社区运行时请使用 scripts/community-runtime.py 修复；原 CrossOver 和游戏均保留。") }
        let manifest = try JSONFile.read(Installation.self, from: layout.manifest)
        let source = URL(fileURLWithPath: manifest.sourceApp)
        guard appVersion(source) == manifest.crossoverVersion else { throw OWError.message("原 CrossOver 版本已改变，需重新准备并验证兼容性。") }
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        let staging = layout.root.appendingPathComponent("RuntimeRepair-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let app = staging.appendingPathComponent("CrossOver.app")
        progress("正在修复独立运行时，保留已有游戏…")
        try Command.clone(source, to: app)
        try patchAndSign(app, archive: archive, staging: staging)
        if fm.fileExists(atPath: layout.runtime.path) {
            let backup = layout.root.appendingPathComponent("Archived/Runtime-" + UUID().uuidString + "/CrossOver.app")
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: layout.runtime, to: backup)
        }
        try fm.createDirectory(at: layout.runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: app, to: layout.runtime)
        progress("独立运行时签名校验通过")
    }

    public func prepareFreeRuntime(archive: URL, sourceBottle: URL? = nil, engineArchive: URL? = nil, repair: Bool = false, progress: @Sendable (String) -> Void = { _ in }) async throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped()
        // A prepared legacy runtime can still need its first Soju game import.
        // Runtime repair must preserve the existing browser compatibility choice.
        let firstImport = !fm.fileExists(atPath: layout.community.appendingPathComponent("prefix-soju26").path)
        let selected = resolveForLaunch(launchProfile())
        let installer = CommunityInstaller(layout: layout)
        try await installer.install(source: sourceBottle ?? detectBottle(), graphicsArchive: archive,
                                    localEngineArchive: engineArchive, replaceRuntime: repair, progress: progress)
        try requireStopped()
        if firstImport { try configureBattleNetBrowser(resetForNewInstallation: true) }
        try applyProfileUnlocked(selected, includeGameFiles: true)
        try verifyRuntime()
        progress("游戏已导入 · 可以启动战网")
    }

    public func prepare(archive: URL, sourceBottle: URL? = nil, sourceApp: URL = URL(fileURLWithPath: "/Applications/CrossOver.app"), progress: @Sendable (String) -> Void = { _ in }) throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped()
        if layout.isPrepared { try verifyRuntime(); progress("独立环境已经准备完成。"); return }
        if fm.fileExists(atPath: layout.manifest.path) { throw OWError.message("已有游戏环境，但运行时缺失。请点“修复运行时”，无需再次克隆游戏。") }
        guard let source = sourceBottle ?? detectBottle() else { throw OWError.message("没有找到已安装的守望先锋。请选择包含 cxbottle.conf 和 drive_c 的 CrossOver 容器。") }
        guard fm.fileExists(atPath: gameExecutable(in: source).path) else { throw OWError.message("所选容器中没有找到默认路径下的 Overwatch.exe。") }
        let version = appVersion(sourceApp)
        guard version == "26.3" || version == "26.3.0" else { throw OWError.message("当前版本仅验证 CrossOver 26.3，检测到 \(version)。") }
        guard try Command.sha256(archive) == Self.patchHash else { throw OWError.message("图形组件校验失败，请重新构建或下载完整 OW120。") }
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", sourceApp.path])
        let running = (try? Command.run("/bin/ps", ["-axo", "comm="])) ?? ""
        guard !running.contains(sourceApp.path + "/Contents/SharedSupport/CrossOver") else { throw OWError.message("请先退出原 CrossOver 的游戏和战网，确保克隆时文件一致。") }
        let before = try fingerprint(source, app: sourceApp)
        let staging = layout.root.appendingPathComponent("Preparation-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        progress("正在克隆 CrossOver 运行时…")
        let stagedApp = staging.appendingPathComponent("CrossOver.app")
        try Command.clone(sourceApp, to: stagedApp)
        progress("正在克隆已有国服安装（APFS 写时复制）…")
        let stagedBottle = staging.appendingPathComponent("ow120")
        try Command.clone(source, to: stagedBottle)
        progress("正在校验并安装 OW 专项图形组件…")
        try patchAndSign(stagedApp, archive: archive, staging: staging)
        // Preserve original settings, but replace only the Documents symlink in our clone.
        try fm.createDirectory(at: layout.documents, withIntermediateDirectories: true)
        let oldDocuments = source.appendingPathComponent("drive_c/users/crossover/Documents").resolvingSymlinksInPath()
        let oldOW = oldDocuments.appendingPathComponent("Overwatch")
        if fm.fileExists(atPath: oldOW.path), !fm.fileExists(atPath: layout.documents.appendingPathComponent("Overwatch").path) { try Command.clone(oldOW, to: layout.documents.appendingPathComponent("Overwatch")) }
        let documentsLink = stagedBottle.appendingPathComponent("drive_c/users/crossover/Documents")
        if fm.fileExists(atPath: documentsLink.path) || (try? fm.destinationOfSymbolicLink(atPath: documentsLink.path)) != nil { try fm.removeItem(at: documentsLink) }
        try fm.createSymbolicLink(at: documentsLink, withDestinationURL: layout.documents)
        let conf = stagedBottle.appendingPathComponent("cxbottle.conf")
        var text = try String(contentsOf: conf, encoding: .utf8)
        text = INI.merge(text, section: "Bottle", values: ["BottleID": UUID().uuidString], quotedKeys: true)
        try Command.write(text, to: conf)
        // Commit both staged directories. Existing incomplete setup is preserved, not overwritten.
        guard !fm.fileExists(atPath: layout.runtime.path), !fm.fileExists(atPath: layout.bottle.path) else { throw OWError.message("存在未完成的 OW120 环境。请先使用“保留备份并重建”，不要覆盖现有目录。") }
        try fm.createDirectory(at: layout.runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.bottles, withIntermediateDirectories: true)
        try fm.moveItem(at: stagedApp, to: layout.runtime)
        do { try fm.moveItem(at: stagedBottle, to: layout.bottle) }
        catch { try? fm.moveItem(at: layout.runtime, to: stagedApp); throw error }
        try fm.createDirectory(at: layout.cache, withIntermediateDirectories: true)
        try fm.createDirectory(at: layout.sessions, withIntermediateDirectories: true)
        let selected = GameProfile.competitive(memoryGB: inspect().memoryGB)
        try applyProfileUnlocked(selected, includeGameFiles: true)
        let installation = Installation(sourceApp: sourceApp.path, sourceBottle: source.path, crossoverVersion: version, createdAt: Date(), patchSHA256: Self.patchHash, sourceFingerprint: before)
        guard try fingerprint(source, app: sourceApp) == before else { throw OWError.message("原环境在克隆时发生变化，请退出原战网后重建。") }
        try JSONFile.write(installation, to: layout.manifest)
        progress("独立国服环境已就绪 · 120 FPS 性能档")
    }

    public func applyProfile(_ profile: GameProfile) throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped(); guard layout.isPrepared else { throw OWError.message("请先准备独立环境。") }
        try applyProfileUnlocked(profile, includeGameFiles: true)
    }
    /// Writes DXMT config even while the game is running. INI and registry wait until Wine exits so they are not overwritten on shutdown.
    public func optimizeFor120() throws {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        guard layout.isPrepared else { throw OWError.message("请先准备独立环境。") }
        try applyProfileUnlocked(GameProfile.competitive(memoryGB: inspect().memoryGB), includeGameFiles: !active())
    }
    private func applyProfileUnlocked(_ profile: GameProfile, includeGameFiles: Bool) throws {
        try profile.validate()
        let profile = displayFitted(profile)
        guard !layout.isCommunity || profile.backend == .dxmt else { throw OWError.message("社区运行时当前只接入 DXMT，请选择性能档或均衡档。") }
        try fm.createDirectory(at: layout.cache, withIntermediateDirectories: true)
        try Command.write(profile.dxmtText, to: layout.dxmtConfig)
        let bottleConf = layout.bottle.appendingPathComponent("cxbottle.conf")
        let old = try String(contentsOf: bottleConf, encoding: .utf8)
        var values = ["CX_GRAPHICS_BACKEND": profile.backend.rawValue, "WINEMSYNC": profile.msync ? "1" : "0", "WINEESYNC": "0", "DXMT_CONFIG_FILE": layout.dxmtConfig.path, "DXMT_USE_DEFAULT_METAL_CACHE": "1", "DXMT_SHADER_CACHE_PATH": layout.cache.path, "DXMT_METALFX_SPATIAL_SWAPCHAIN": "0", "MTL_HUD_ENABLED": profile.showHUD ? "1" : "0", "MTL_SHADER_VALIDATION": "0", "WINEDEBUG": "-all"]
        // Presence of Metal debug variables can activate instrumentation even
        // with value 0. Remove them entirely from the cloned bottle as well.
        let clean = INI.remove(old, section: "EnvironmentVariables", keys: ["MTL_HUD_ENABLED", "MTL_SHADER_VALIDATION", "MTL_HUD_LOGGING_ENABLED"])
        values.removeValue(forKey: "MTL_HUD_ENABLED"); values.removeValue(forKey: "MTL_SHADER_VALIDATION")
        if profile.showHUD { values["MTL_HUD_ENABLED"] = "1" }
        try Command.write(INI.merge(clean, section: "EnvironmentVariables", values: values, quotedKeys: true), to: bottleConf)
        try JSONFile.write(profile, to: layout.profileFile)
        try JSONFile.write(profile, to: layout.launchProfileFile)
        guard includeGameFiles else { return }
        let previous = (try? String(contentsOf: layout.settings, encoding: .utf8)) ?? ""
        if !previous.isEmpty {
            let backup = layout.root.appendingPathComponent("SettingsBackups/\(UUID().uuidString).ini")
            try Command.write(previous, to: backup)
        }
        try Command.write(INI.merge(previous, section: "Render.13", values: profile.gameOverrides), to: layout.settings)
        let registry = layout.bottle.appendingPathComponent("user.reg")
        if fm.fileExists(atPath: registry.path) {
            let text = try String(contentsOf: registry, encoding: .utf8)
            try Command.write(profile.displayRegistry(text, community: layout.isCommunity), to: registry)
        }
        try configureBattleNetBrowser()
        if layout.isSoju { try prepareGameGraphicsPath() }
    }
    func prepareGameGraphicsPath() throws {
        guard layout.isSoju else { throw OWError.message("标准图形组件安装仅用于 OW120 社区 Wine 11。") }
        try requireStopped()
        try CommunityGraphics.install(engine: layout.engine, prefix: layout.bottle,
            pack: layout.community.appendingPathComponent("graphics/dxmt-ow2-pack"),
            backup: layout.community.appendingPathComponent("GraphicsBackups/soju26-before-dxmt"))
    }
    func configureBattleNetBrowser(resetForNewInstallation: Bool = false) throws {
        let config = layout.bottle.appendingPathComponent("drive_c/users/crossover/AppData/Roaming/Battle.net/Battle.net.config")
        guard fm.fileExists(atPath: config.path), let data = try? Data(contentsOf: config),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var client = object["Client"] as? [String: Any] ?? [:]
        // Battle.net's webview setting is separate from the game's DXMT backend.
        // Preserve a browser compatibility choice instead of undoing it at launch.
        if !layout.isSoju || client["HardwareAcceleration"] == nil || resetForNewInstallation {
            client["HardwareAcceleration"] = "false"
        }
        object["Client"] = client
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: config, options: .atomic)
    }

    public func wineEnvironment(session: URL? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Remove inherited Wine settings so invoking from another bottle cannot redirect this run.
        for key in Array(env.keys) where key.hasPrefix("WINE") || key.hasPrefix("CX_") || key.hasPrefix("DXMT_") || key.hasPrefix("DYLD_") || key.hasPrefix("MTL_") { env.removeValue(forKey: key) }
        let selected = profile()
        env["CX_BOTTLE_PATH"] = layout.bottles.path
        env["CX_BOTTLE"] = "ow120"
        env["WINEPREFIX"] = layout.bottle.path
        env["WINEDEBUG"] = "-all"
        env["WINEMSYNC"] = selected.msync ? "1" : "0"
        env["WINEESYNC"] = "0"
        env["CX_GRAPHICS_BACKEND"] = selected.backend.rawValue
        env["DXMT_CONFIG_FILE"] = layout.dxmtConfig.path
        env["DXMT_SHADER_CACHE_PATH"] = layout.cache.path
        env["DXMT_USE_DEFAULT_METAL_CACHE"] = "1"
        env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "0"
        if selected.showHUD { env["MTL_HUD_ENABLED"] = "1" }
        if layout.isCommunity {
            env.removeValue(forKey: "CX_BOTTLE_PATH"); env.removeValue(forKey: "CX_BOTTLE")
            env.removeValue(forKey: "CX_GRAPHICS_BACKEND")
            env["DYLD_FALLBACK_LIBRARY_PATH"] = (layout.isSoju ? layout.engine.appendingPathComponent("lib") : layout.community.appendingPathComponent("Template-1.0.19.app/Contents/Frameworks")).path + ":/usr/lib:/usr/libexec:/usr/lib/system"
            if !layout.isSoju { env["WINEDLLPATH_PREPEND"] = layout.community.appendingPathComponent("graphics/dxmt-ow2-pack").path }
            env["ROSETTA_ADVERTISE_AVX"] = "1"
            if layout.isSoju {
                env["WINE_SIMULATE_WRITECOPY"] = "1"
            }
            env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree,mshtml="
        }
        if let session { env["DXMT_FRAME_LOG"] = session.appendingPathComponent("frames").path }
        return env
    }
    public func smokeTest() throws -> String {
        guard layout.isPrepared else { throw OWError.message("尚未准备环境。") }
        try verifyRuntime()
        return try Command.run(layout.engine.appendingPathComponent("bin/wine").path, layout.wineArguments(["cmd.exe", "/c", "echo OW120_RUNTIME_OK"]), environment: wineEnvironment())
    }
    public func launch(selectedProfile: GameProfile? = nil, graphicsProbe: URL? = nil) async throws -> SessionInfo {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        guard layout.isPrepared else { throw OWError.message("请先准备独立环境。") }
        try requireStopped()
        try verifyRuntime()
        if layout.isCommunity, let graphicsProbe { try requireSystemGraphics(helper: graphicsProbe) }
        do { _ = try warmShaderCacheUnlocked() }
        catch {
            // Cache reuse is optional. A corrupt old database must not prevent
            // the working game from starting with its existing cache.
            try? JSONFile.write(["error": error.localizedDescription], to: layout.root.appendingPathComponent("Reports/shader-cache-migration-error.json"))
        }
        let selected = resolveForLaunch(selectedProfile ?? launchProfile())
        try applyProfileUnlocked(selected, includeGameFiles: true)
        let folder = layout.sessions.appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(6))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = SessionInfo(profile: selected, folder: folder)
        try JSONFile.write(session, to: folder.appendingPathComponent("session.json"))
        try JSONFile.write(inspect(), to: folder.appendingPathComponent("machine.json"))
        let launcher = layout.bottle.appendingPathComponent("drive_c/Program Files (x86)/Battle.net/Battle.net.exe")
        guard fm.fileExists(atPath: launcher.path) else { throw OWError.message("独立容器中找不到战网客户端。") }
        if layout.isCommunity {
            // Wine resolves the Agent caller's relative executable against its CWD.
            // Supply the unchanged signed client; never disable signature verification.
            for version in try fm.contentsOfDirectory(at: launcher.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey]) where version.lastPathComponent.hasPrefix("Battle.net.") && (try? version.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let target = version.appendingPathComponent("Battle.net.exe")
                if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: launcher, to: target) }
            }
        }
        let log = folder.appendingPathComponent("launcher.log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = layout.engine.appendingPathComponent("bin/wine")
        // --cx-app searches by basename or accepts a Windows drive path; a Unix
        // absolute path is interpreted as a search pattern and never matches.
        var arguments = ["C:\\Program Files (x86)\\Battle.net\\Battle.net.exe"]
        if layout.isSoju { arguments.append("--in-process-gpu") }
        arguments.append("--exec=launch Pro")
        process.arguments = layout.wineArguments(arguments)
        process.environment = wineEnvironment(session: folder)
        process.currentDirectoryURL = launcher.deletingLastPathComponent()
        process.standardOutput = handle; process.standardError = handle
        try process.run(); try? handle.close()
        children.removeAll { !$0.isRunning }; children.append(process)
        try Command.write(folder.path, to: layout.root.appendingPathComponent("latest-session.txt"))
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            if !process.isRunning {
                if process.terminationStatus != 0 {
                    let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    throw OWError.message("战网启动失败（\(process.terminationStatus)）。\n\(detail.suffix(2500))")
                }
                break
            }
        }
        return session
    }
    public func warmShaderCache() throws -> Int {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped()
        return try warmShaderCacheUnlocked()
    }
    private func warmShaderCacheUnlocked() throws -> Int {
        guard layout.isSoju else { return 0 }
        let source = layout.root.appendingPathComponent("ShaderCache/dxmt-0.80-ow2-0.2/shaders_320.db")
        let destination = layout.cache.appendingPathComponent("shaders_320.db")
        guard fm.fileExists(atPath: source.path) else { return 0 }
        let oldLibraries = layout.root.appendingPathComponent("Runtime/CrossOver.app/Contents/SharedSupport/CrossOver/lib/dxmt/x86_64-windows")
        let currentLibraries = layout.engine.appendingPathComponent("lib/wine/x86_64-windows")
        for name in ["d3d11.dll", "dxgi.dll", "winemetal.dll"] {
            let old = oldLibraries.appendingPathComponent(name), current = currentLibraries.appendingPathComponent(name)
            guard fm.fileExists(atPath: old.path), fm.fileExists(atPath: current.path), try Command.sha256(old) == Command.sha256(current) else { return 0 }
        }
        let receipt = layout.root.appendingPathComponent("Reports/shader-cache-migration.json")
        let wal = URL(fileURLWithPath: source.path + "-wal")
        let fingerprint = try Command.sha256(source) + (fm.fileExists(atPath: wal.path) ? "|" + Command.sha256(wal) : "")
        let fileID = (try? fm.attributesOfItem(atPath: destination.path)[.systemFileNumber]).map { String(describing: $0) } ?? "missing"
        if let previous = try? JSONFile.read([String: String].self, from: receipt), previous["sourceSHA256"] == fingerprint,
           fm.fileExists(atPath: destination.path), previous["destination"] == destination.path, previous["destinationFileID"] == fileID { return 0 }
        let backup = layout.root.appendingPathComponent("CacheBackups/\(UUID().uuidString)-shaders_320.db")
        let count = try ShaderCacheMigration.merge(source: source, destination: destination, backup: backup)
        let newFileID = (try? fm.attributesOfItem(atPath: destination.path)[.systemFileNumber]).map { String(describing: $0) } ?? "missing"
        try JSONFile.write(["sourceSHA256": fingerprint, "destination": destination.path, "destinationFileID": newFileID, "backup": backup.path, "importedEntries": String(count)], to: receipt)
        return count
    }
    public func stop() throws {
        guard layout.isPrepared, active() else { return }
        try verifyRuntime()
        let env = wineEnvironment()
        _ = try Command.run(layout.engine.appendingPathComponent("bin/wineserver").path, ["-k"], environment: env)
        _ = try Command.run(layout.engine.appendingPathComponent("bin/wineserver").path, ["-w"], environment: env)
    }
    public func archiveEnvironment() throws -> URL {
        let lock = try OperationLock(layout.root); defer { withExtendedLifetime(lock) {} }
        try requireStopped()
        guard !layout.isCommunity else { throw OWError.message("社区环境请通过交接文档管理，暂不自动归档。") }
        let archive = layout.root.appendingPathComponent("Archived/" + UUID().uuidString)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        for name in ["Runtime", "Bottles", "Documents", "installation.json", "profile.json", "dxmt.conf"] {
            let source = layout.root.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: archive.appendingPathComponent(name)) }
        }
        return archive
    }
    public func latestSession() -> SessionInfo? {
        guard let file = try? String(contentsOf: layout.root.appendingPathComponent("latest-session.txt"), encoding: .utf8) else { return nil }
        return try? JSONFile.read(SessionInfo.self, from: URL(fileURLWithPath: file.trimmingCharacters(in: .whitespacesAndNewlines)).appendingPathComponent("session.json"))
    }
}
