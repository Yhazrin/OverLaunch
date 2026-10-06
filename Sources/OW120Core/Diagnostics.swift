import Foundation

public struct HealthCheck: Identifiable, Sendable {
    public enum State: String, Sendable { case ready, attention, unavailable }
    public var id: String
    public var title: String
    public var detail: String
    public var state: State
}

public struct StartupIssue: Equatable, Sendable {
    public var title: String
    public var detail: String
    public static func detect(gameLog: String, launcherLog: String) -> StartupIssue? {
        if launcherLog.contains("rosetta error: Attachment of code signature supplement failed") && launcherLog.contains("libMetalMetricsInterpose") {
            return StartupIssue(title: "系统图形组件启动失败", detail: "Rosetta 未能加载 macOS 的 Metal 性能组件。请先关闭游戏并重启 Mac；若仍复现，需要在较新的 macOS 版本验证。当前还没有可用的游戏帧记录。")
        }
        if gameLog.contains("Selected graphics API is not supported") || gameLog.contains("0xE0010110") {
            return StartupIssue(title: "图形初始化失败 · 0xE0010110", detail: "游戏没有获得可用的 DirectX 图形接口。退出战网后，使用“修复运行组件”重新校验国服图形配置。")
        }
        return nil
    }
}

enum LogTail {
    static func read(_ file: URL, limit: Int = 256_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "" }
        try? handle.seek(toOffset: size > UInt64(limit) ? size - UInt64(limit) : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
}

extension EnvironmentService {
    public func healthChecks() -> [HealthCheck] {
        let fm = FileManager.default
        let machine = inspect()
        var checks = [HealthCheck(id: "runtime", title: "免费运行组件", detail: layout.isSoju ? "独立 Wine 引擎 · 无 CrossOver 授权依赖" : "尚未迁移到免费引擎", state: layout.isSoju && fm.fileExists(atPath: layout.engine.appendingPathComponent("bin/wine").path) ? .ready : .unavailable)]
        let game = gameExecutable(in: layout.bottle)
        checks.append(HealthCheck(id: "game", title: "国服游戏文件", detail: fm.fileExists(atPath: game.path) ? "已导入本机安装" : "请先导入已有战网容器", state: fm.fileExists(atPath: game.path) ? .ready : .unavailable))
        let pack = layout.community.appendingPathComponent("graphics/dxmt-ow2-pack/x86_64-windows/d3d11.dll")
        let installed = layout.engine.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")
        let graphicsOK = layout.isSoju && (try? Command.sha256(pack)) != nil && (try? Command.sha256(pack)) == (try? Command.sha256(installed))
        checks.append(HealthCheck(id: "graphics", title: "国服图形组件", detail: graphicsOK ? "64 位 DXMT 已安装 · 战网使用独立渲染配置" : "需要校验或修复图形组件", state: graphicsOK ? .ready : .attention))
        let system = systemGraphicsResult()
        checks.append(HealthCheck(id: "system-graphics", title: "系统图形环境", detail: system?.issue?.title ?? (system?.rosettaSucceeded == true ? "基础 Rosetta 窗口渲染通过 · 游戏待实测" : "尚未检查 · 点“重新检查”或启动时检测"), state: system == nil ? .attention : system?.issue == nil ? .ready : .unavailable))
        checks.append(HealthCheck(id: "display", title: "显示与供电", detail: machine.lowPowerMode ? "低电量模式开启，建议接电后关闭" : machine.maximumDisplayHz < 119 && machine.maximumDisplayHz > 0 ? "显示器最高刷新率低于 120 Hz" : "已选择 120 FPS 目标档", state: machine.lowPowerMode || (machine.maximumDisplayHz > 0 && machine.maximumDisplayHz < 119) ? .attention : .ready))
        return checks
    }

    public func startupIssue() -> StartupIssue? {
        let system = systemGraphicsResult()
        if let issue = system?.issue { return issue }
        guard let session = latestSession() else { return nil }
        let game = layout.documents.appendingPathComponent("Overwatch/Logs/守望先锋.log")
        let modified = (try? game.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let gameText = modified >= session.startedAt ? LogTail.read(game) : ""
        let issue = StartupIssue.detect(gameLog: gameText, launcherLog: LogTail.read(session.folder.appendingPathComponent("launcher.log"), limit: 1_000_000))
        if issue?.title == "系统图形组件启动失败", let system, system.rosettaSucceeded, system.checkedAt > session.startedAt { return nil }
        return issue
    }

    public func exportDiagnostics() throws -> URL {
        let checks = healthChecks()
        let machine = inspect()
        let issue = startupIssue()
        let report = """
        # OW120 本机诊断

        Mac: \(machine.chip) / \(machine.memoryGB) GB
        macOS: \(machine.macOS)
        运行组件: \(layout.runtimeName)
        帧率目标: \(profile().targetFPS) FPS（不代表实测成绩）

        \(checks.map { "- [\($0.state.rawValue)] \($0.title)：\($0.detail)" }.joined(separator: "\n"))

        \(issue.map { "启动错误：\($0.title)\n\($0.detail)" } ?? "未识别到已知启动错误；仍需确认游戏画面。")

        本报告不包含战网账号、令牌或原始日志。文件仅保存在本机。
        """
        let destination = layout.root.appendingPathComponent("Reports/diagnostics-\(UUID().uuidString).md")
        try Command.write(report, to: destination)
        return destination
    }
}
