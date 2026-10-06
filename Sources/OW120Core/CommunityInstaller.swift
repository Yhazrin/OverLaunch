import Foundation

/// Installs the free runtime directly. CrossOver is only an optional source of
/// already-downloaded game files; its application and license are not copied.
struct CommunityInstaller {
    static let engineURL = URL(string: "https://github.com/BCD1210/soju/releases/download/engine-v1.5/wine-engine-x86_64.tar.xz")!
    static let engineHash = "7b96a4407308493ae92bebe96039bbc8d0bf3b86c22cb99c782f73cf7be3738e"
    let layout: Layout
    private let fm = FileManager.default

    static func sourceFingerprint(_ source: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for name in ["cxbottle.conf", "user.reg", "system.reg"] {
            let file = source.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { result[name] = try Command.sha256(file) }
        }
        return result
    }

    static func validateMembers(_ members: String) throws {
        guard !members.isEmpty, members.split(separator: "\n").allSatisfy({ line in
            !line.hasPrefix("/") && !line.split(separator: "/").contains("..")
        }) else { throw OWError.message("运行组件归档包含无效路径。") }
    }

    private func extract(_ archive: URL, to destination: URL) throws {
        try Self.validateMembers(Command.run("/usr/bin/tar", ["-tf", archive.path]))
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Command.run("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
    }

    private func engineArchive(localArchive: URL?, progress: @Sendable (String) -> Void) async throws -> URL {
        let cache = layout.root.appendingPathComponent("Downloads/soju-engine-v1.5.tar.xz")
        if let localArchive {
            guard try Command.sha256(localArchive) == Self.engineHash else { throw OWError.message("免费引擎归档校验失败。") }
            return localArchive
        }
        if fm.fileExists(atPath: cache.path), try Command.sha256(cache) == Self.engineHash { return cache }
        progress("正在下载免费运行组件（约 367 MB）…")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: Self.engineURL)
        defer { try? fm.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              try Command.sha256(temporary) == Self.engineHash else { throw OWError.message("免费引擎下载不完整或校验失败，请重试。") }
        try fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: cache.path) { try fm.removeItem(at: cache) }
        try fm.moveItem(at: temporary, to: cache)
        return cache
    }

    func install(source: URL?, graphicsArchive: URL, localEngineArchive: URL? = nil,
                 replaceRuntime: Bool = false, progress: @Sendable (String) -> Void) async throws {
        guard try Command.sha256(graphicsArchive) == EnvironmentService.patchHash else { throw OWError.message("图形组件校验失败，请重新下载 OW120。") }
        let community = layout.community
        let engine = community.appendingPathComponent("soju26")
        let prefix = community.appendingPathComponent("prefix-soju26")
        let documents = community.appendingPathComponent("Documents-soju26")
        let needsImport = !fm.fileExists(atPath: prefix.path)
        var originalFingerprint: [String: String] = [:]
        if needsImport {
            guard let source, fm.fileExists(atPath: source.appendingPathComponent("drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe").path),
                  fm.fileExists(atPath: source.appendingPathComponent("drive_c/Program Files (x86)/Battle.net/Battle.net.exe").path) else {
                throw OWError.message("请选择包含战网和守望先锋的已有游戏容器。")
            }
            let processes = try Command.run("/bin/ps", ["-axo", "comm="])
            guard !processes.contains("/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/") else {
                throw OWError.message("请先退出源容器中的战网与游戏，再导入。")
            }
            originalFingerprint = try Self.sourceFingerprint(source)
        }
        let staging = layout.root.appendingPathComponent("Setup-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let needsEngine = replaceRuntime || !fm.fileExists(atPath: engine.appendingPathComponent("bin/wine").path)
        let stagedEngine = staging.appendingPathComponent("engine")
        if needsEngine {
            let archive = try await engineArchive(localArchive: localEngineArchive, progress: progress)
            progress("正在校验并安装免费引擎…")
            try extract(archive, to: stagedEngine)
            for name in ["wine", "wineserver"] { try Command.run("/usr/bin/codesign", ["--verify", "--strict", stagedEngine.appendingPathComponent("bin/" + name).path]) }
        }
        let stagedGraphics = staging.appendingPathComponent("graphics")
        try extract(graphicsArchive, to: stagedGraphics)
        let pack = stagedGraphics.appendingPathComponent("dxmt-ow2-pack")
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", pack.appendingPathComponent("x86_64-unix/winemetal.so").path])
        let stagedPrefix = staging.appendingPathComponent("prefix")
        let stagedDocuments = staging.appendingPathComponent("documents")
        if needsImport, let source {
            progress("正在导入已有国服游戏…")
            try Command.clone(source, to: stagedPrefix)
            let sourceDocuments = source.appendingPathComponent("drive_c/users/crossover/Documents").resolvingSymlinksInPath()
            try fm.createDirectory(at: stagedDocuments, withIntermediateDirectories: true)
            let overwatchDocuments = sourceDocuments.appendingPathComponent("Overwatch")
            if fm.fileExists(atPath: overwatchDocuments.path) { try Command.clone(overwatchDocuments, to: stagedDocuments.appendingPathComponent("Overwatch")) }
            // Replace only the link in our clone, never follow it into the source.
            let link = stagedPrefix.appendingPathComponent("drive_c/users/crossover/Documents")
            if fm.fileExists(atPath: link.path) || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil { try fm.removeItem(at: link) }
            try fm.createSymbolicLink(at: link, withDestinationURL: documents)
            if !fm.fileExists(atPath: stagedPrefix.appendingPathComponent("cxbottle.conf").path) { try Command.write("[Bottle]\n", to: stagedPrefix.appendingPathComponent("cxbottle.conf")) }
            guard try Self.sourceFingerprint(source) == originalFingerprint else { throw OWError.message("源游戏配置在导入时发生变化，请退出源战网后重试。") }
            guard !fm.fileExists(atPath: documents.path) else { throw OWError.message("存在未完成的游戏导入。请在支持页面检查导入目录。") }
        }
        // A new engine is smoke-tested before replacing the installed engine.
        if needsEngine {
            progress("正在检查 Windows 启动能力…")
            let testPrefix = staging.appendingPathComponent("smoke-prefix")
            let env = Self.baseEnvironment(engine: stagedEngine, prefix: testPrefix)
            defer { _ = try? Command.run(stagedEngine.appendingPathComponent("bin/wineserver").path, ["-k"], environment: env, allowFailure: true) }
            let result = try Command.run(stagedEngine.appendingPathComponent("bin/wine").path, ["cmd.exe", "/c", "echo OW120_FREE_RUNTIME_OK"], environment: env)
            guard result.contains("OW120_FREE_RUNTIME_OK") else { throw OWError.message("运行组件启动检查失败，已保留现有环境。") }
            _ = try Command.run(stagedEngine.appendingPathComponent("bin/wineserver").path, ["-k"], environment: env, allowFailure: true)
            try Command.run(stagedEngine.appendingPathComponent("bin/wineserver").path, ["-w"], environment: env)
        }
        try fm.createDirectory(at: community, withIntermediateDirectories: true)
        var moved: [(URL, URL)] = []
        let archived = layout.root.appendingPathComponent("Archived/FreeRuntime-" + UUID().uuidString)
        var saved: [(URL, URL)] = []
        do {
            for (candidate, destination) in [(needsEngine ? stagedEngine : nil, engine), (stagedGraphics, community.appendingPathComponent("graphics")), (needsImport ? stagedDocuments : nil, documents), (needsImport ? stagedPrefix : nil, prefix)] {
                guard let candidate else { continue }
                if fm.fileExists(atPath: destination.path) {
                    let backup = archived.appendingPathComponent(destination.lastPathComponent)
                    try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: destination, to: backup); saved.append((backup, destination))
                }
                try fm.moveItem(at: candidate, to: destination); moved.append((destination, candidate))
            }
            try CommunityGraphics.install(engine: engine, prefix: prefix, pack: community.appendingPathComponent("graphics/dxmt-ow2-pack"), backup: community.appendingPathComponent("GraphicsBackups/soju26-before-dxmt"))
            let oldSelection = try? Data(contentsOf: layout.root.appendingPathComponent("active-runtime"))
            let oldManifest = try? Data(contentsOf: layout.manifest)
            do {
                if needsImport, let source {
                    var installation = Installation(sourceApp: "", sourceBottle: source.path, crossoverVersion: "", createdAt: Date(), patchSHA256: EnvironmentService.patchHash, sourceFingerprint: originalFingerprint)
                    installation.version = 2
                    try JSONFile.write(installation, to: layout.manifest)
                }
                try Command.write("community-soju26\n", to: layout.root.appendingPathComponent("active-runtime"))
            } catch {
                let selection = layout.root.appendingPathComponent("active-runtime")
                if let oldSelection { try? oldSelection.write(to: selection, options: .atomic) }
                else { try? fm.removeItem(at: selection) }
                if let oldManifest { try? oldManifest.write(to: layout.manifest, options: .atomic) }
                else { try? fm.removeItem(at: layout.manifest) }
                throw error
            }
        } catch {
            for (destination, candidate) in moved.reversed() { try? fm.moveItem(at: destination, to: candidate) }
            for (backup, destination) in saved.reversed() { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
        progress("导入完成 · 免费运行环境已就绪")
    }

    static func baseEnvironment(engine: URL, prefix: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { key, _ in !["WINE", "CX_", "DYLD_", "DXMT_", "MTL_"].contains(where: key.hasPrefix) }
        env["WINEPREFIX"] = prefix.path; env["WINEDEBUG"] = "-all"; env["WINEMSYNC"] = "1"; env["WINEESYNC"] = "0"
        env["ROSETTA_ADVERTISE_AVX"] = "1"; env["WINE_SIMULATE_WRITECOPY"] = "1"
        env["DYLD_FALLBACK_LIBRARY_PATH"] = engine.appendingPathComponent("lib").path + ":/usr/lib:/usr/libexec:/usr/lib/system"
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree,mshtml="
        return env
    }
}

enum CommunityGraphics {
    static func install(engine: URL, prefix: URL, pack: URL, backup: URL) throws {
        let fm = FileManager.default
        var files = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"].map {
            (pack.appendingPathComponent("x86_64-windows/" + $0), engine.appendingPathComponent("lib/wine/x86_64-windows/" + $0), "engine/" + $0)
        }
        files += [(pack.appendingPathComponent("x86_64-unix/winemetal.so"), engine.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so"), "engine/winemetal.so"), (pack.appendingPathComponent("x86_64-windows/winemetal.dll"), prefix.appendingPathComponent("drive_c/windows/system32/winemetal.dll"), "prefix/winemetal.dll")]
        for (source, _, _) in files { guard fm.fileExists(atPath: source.path) else { throw OWError.message("缺少图形组件：" + source.lastPathComponent) } }
        for (source, destination, key) in files {
            if fm.fileExists(atPath: destination.path), try Command.sha256(source) == Command.sha256(destination) { continue }
            let saved = backup.appendingPathComponent(key)
            if fm.fileExists(atPath: destination.path), !fm.fileExists(atPath: saved.path) { try Command.clone(destination, to: saved) }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source).write(to: destination, options: .atomic)
        }
        try Command.run("/usr/bin/codesign", ["--verify", "--strict", engine.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so").path])
    }
}
