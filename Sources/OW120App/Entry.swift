import SwiftUI
import OW120Core

@main
struct Entry {
    @MainActor static func main() async {
        if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            await CLI.run()
        } else { LauncherTheme.registerFonts(); OW120Application.main() }
    }
}

struct OW120Application: App {
    var body: some Scene {
        WindowGroup("OverLaunch") { LauncherView().preferredColorScheme(.light) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: min(1120, max(660, (NSScreen.main?.visibleFrame.width ?? 1200) - 60)),
                         height: min(780, max(500, (NSScreen.main?.visibleFrame.height ?? 900) - 60)))
            .windowResizability(.contentMinSize)
    }
}

enum Assets {
    static var heroIcons: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("HeroIcons")
        if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("catalog.json").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/HeroIcons")
    }
    static var graphicsProbe: URL {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/OW120GraphicsProbe")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/OverLaunch.app/Contents/MacOS/OW120GraphicsProbe")
    }
    static var archive: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("dxmt-ow2-pack-v0.2.tar.gz")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/dxmt-ow2-pack-v0.2.tar.gz")
    }
}

enum CLI {
    static func run() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let layout = ProcessInfo.processInfo.environment["OW120_ROOT"].map { Layout(root: URL(fileURLWithPath: $0)) } ?? Layout()
        let env = EnvironmentService(layout: layout)
        do {
            switch args.first {
            case "--list-icons":
                let assets = try await AppAppearance()
                print("default\t默认 OW 标志")
                for hero in assets.catalog.heroes { print("\(hero.id)\t\(hero.title) / \(hero.englishName)") }
            case "--set-icon":
                guard let id = args.dropFirst().first else { throw OWError.message("用法：--set-icon default/英雄英文ID。--list-icons 查看全部图标。") }
                let assets = try await AppAppearance()
                guard assets.catalog.contains(id) else { throw OWError.message("英雄图标不存在。") }
                let selected = LauncherAppearance(iconID: id)
                try await assets.apply(selected)
                try AppearanceStore(root: layout.root).save(selected, catalog: assets.catalog)
                print("已保存应用图标：" + id)
            case "--doctor":
                let data = try JSONEncoder().encode(await env.inspect()); print(String(decoding: data, as: UTF8.self))
            case "--prepare":
                let sourceIndex = args.firstIndex(of: "--source")
                let source = sourceIndex.flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil }
                let engineIndex = args.firstIndex(of: "--engine-archive")
                let engine = engineIndex.flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil }
                try await env.prepareFreeRuntime(archive: Assets.archive, sourceBottle: source, engineArchive: engine) { print($0); fflush(stdout) }
            case "--smoke-test": print(try await env.smokeTest())
            case "--verify-runtime": try await env.verifyRuntime(); print("PRIVATE_RUNTIME_SIGNATURE_VALID")
            case "--repair-runtime":
                let index = args.firstIndex(of: "--engine-archive")
                let engine = index.flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil }
                try await env.prepareFreeRuntime(archive: Assets.archive, engineArchive: engine, repair: true) { print($0); fflush(stdout) }
            case "--health":
                for check in await env.healthChecks() { print("\(check.state.rawValue): \(check.title) — \(check.detail)") }
                if let issue = await env.startupIssue() { print("\(issue.title): \(issue.detail)") }
            case "--graphics-check":
                let result = try await env.checkSystemGraphics(helper: Assets.graphicsProbe)
                print("native=\(result.nativeSucceeded), rosetta=\(result.rosettaSucceeded), systemMetalSignatureFailure=\(result.rosettaMetalSignatureFailure)")
                if let issue = result.issue { throw OWError.message(issue.title + "。" + issue.detail) }
            case "--diagnostics": print(try await env.exportDiagnostics().path)
            case "--verify-original": print(try await env.verifyOriginal() ? "ORIGINAL_UNCHANGED" : "ORIGINAL_CHANGED_SINCE_IMPORT")
            case "--launch":
                let session = try await env.launch(graphicsProbe: Assets.graphicsProbe); print("SESSION=" + session.folder.path)
            case "--stop": try await env.stop(); print("OverLaunch 已停止。")
            case "--config-mode":
                guard let name = args.dropFirst().first, let mode = ConfigurationMode(rawValue: name) else { throw OWError.message("用法：--config-mode automatic/performance/balanced/clarity/manual") }
                var profile = LaunchConfiguration.match(mode, machine: await env.inspect(), current: await env.launchProfile())
                profile.configurationMode = mode
                try await env.saveLaunchProfile(profile)
                print("已保存：\(mode.title)，下次启动生效。")
            case "--optimize":
                try await env.optimizeFor120()
                print(await env.active() ? "已写入 DXMT 配置。请结束本局后从 OverLaunch 停止并重新启动。" : "已应用无边框 / 关闭 Retina / 保留着色器 IR 的 120 FPS 配置。")
            case "--profile":
                var profile = args.dropFirst().first == "balanced" ? GameProfile.balanced : GameProfile()
                if args.dropFirst().first == "d3dmetal" { profile.backend = .d3dmetal }
                try await env.applyProfile(profile); profile = await env.profile(); print("已应用 \(profile.width)×\(profile.height) / \(profile.targetFPS) FPS / \(profile.backend.rawValue)")
            case "--frame-pacing":
                guard let mode = args.dropFirst().first, ["game", "metal"].contains(mode) else { throw OWError.message("用法：--frame-pacing game/metal。关闭游戏与战网后应用。") }
                var profile = await env.profile(); profile.metalFramePacing = mode == "metal"; profile.configurationMode = .manual
                try await env.applyProfile(profile)
                print(mode == "game" ? "已改为游戏帧率限制，目标仍为 \(profile.targetFPS) FPS。" : "已恢复 Metal 帧率同步，目标为 \(profile.targetFPS) FPS。")
            case "--render-scale":
                guard let text = args.dropFirst().first, let percent = Int(text) else { throw OWError.message("用法：--render-scale 50..100。保存到下次启动，不修改运行中的游戏。") }
                var profile = await env.launchProfile(); profile.renderScalePercent = percent; profile.configurationMode = .manual
                try await env.saveLaunchProfile(profile)
                print("已保存 \(profile.width)×\(profile.height) 输出 / \(percent)% 3D 渲染 / \(profile.targetFPS) FPS 目标，下次启动生效。")
            case "--warm-cache": print("已合并兼容着色器缓存：\(try await env.warmShaderCache()) 条。")
            case "--archive": print(try await env.archiveEnvironment().path)
            case "--poll", "--benchmark-start", "--benchmark-end", "--report":
                guard let session = await env.latestSession() else { throw OWError.message("没有启动记录。") }
                let monitor = TelemetryService(environment: env)
                let result = await monitor.poll(session)
                if args.first == "--report" { print(try await monitor.exportReport(result.session).path) }
                else if args.first == "--poll" {
                    print(result.status); print("winePID=\(result.session.gamePID ?? 0), frames=\(result.totalFrames)")
                    if let m = result.metrics { print(String(decoding: try JSONEncoder().encode(m), as: UTF8.self)) }
                } else {
                    _ = try await monitor.mark(result.session, start: args.first == "--benchmark-start", totalFrames: result.totalFrames)
                    print(args.first == "--benchmark-start" ? "实战采样已开始" : "实战采样已结束")
                }
            default:
                print("OverLaunch: --doctor | --prepare [--source 容器目录] [--engine-archive 文件] | --launch | --stop | --config-mode automatic/performance/balanced/clarity/manual | --render-scale 50..100 | --list-icons | --set-icon 英雄ID/default | --profile performance/balanced/d3dmetal | --frame-pacing game/metal | --poll | --benchmark-start | --benchmark-end | --report | --health | --graphics-check | --diagnostics | --repair-runtime | --verify-original")
            }
        } catch { fputs("OverLaunch: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
