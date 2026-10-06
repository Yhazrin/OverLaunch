import Foundation
import Darwin

/// A basic system rendering check, not a game compatibility or FPS benchmark.
public struct SystemGraphicsResult: Codable, Sendable {
    public var checkedAt: Date
    public var bootSession: String
    public var nativeSucceeded: Bool
    public var rosettaSucceeded: Bool
    public var rosettaMetalSignatureFailure: Bool
    public var timedOut: Bool

    public func applies(to boot: String) -> Bool { !boot.isEmpty && bootSession == boot }
    public var issue: StartupIssue? {
        if !nativeSucceeded && rosettaSucceeded {
            return StartupIssue(title: "系统原生图形测试未通过", detail: "macOS 原生 Metal 窗口测试未通过。请保存工作并重启 Mac，再重新检查。")
        }
        guard !rosettaSucceeded else { return nil }
        if rosettaMetalSignatureFailure {
            return StartupIssue(title: "系统 Rosetta 图形测试失败", detail: "独立 Metal 窗口测试也无法加载 macOS 图形库。请保存工作并重启 Mac，再点“重新检查”；若仍复现，需要在较新的 macOS 版本验证。重新安装游戏组件无法修复这个系统库错误。")
        }
        return StartupIssue(title: "系统图形测试未通过", detail: timedOut ? "基础图形测试超时。请关闭游戏后重启 Mac，再重新检查。" : "Rosetta 基础窗口渲染未通过。请保存诊断报告，重启 Mac 后重新检查。")
    }
}

enum SystemGraphicsProbe {
    static func bootSession() -> String {
        ((try? Command.run("/usr/sbin/sysctl", ["-n", "kern.bootsessionuuid"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func run(_ helper: URL) throws -> SystemGraphicsResult {
        guard FileManager.default.fileExists(atPath: helper.path) else { throw OWError.message("缺少图形检查组件，请重新安装 OW120。") }
        try Command.run("/usr/bin/codesign", ["--verify", "--strict", helper.path])
        let native = try attempt(helper, architecture: "arm64")
        let translated = try attempt(helper, architecture: "x86_64")
        return SystemGraphicsResult(checkedAt: Date(), bootSession: bootSession(),
            nativeSucceeded: native.success, rosettaSucceeded: translated.success,
            rosettaMetalSignatureFailure: translated.output.contains("Attachment of code signature supplement failed") && translated.output.contains("libMetalMetricsInterpose"),
            timedOut: native.timedOut || translated.timedOut)
    }
    private static func attempt(_ helper: URL, architecture: String) throws -> (success: Bool, timedOut: Bool, output: String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        // arch is safe here: this native helper does not need Wine's DYLD_*.
        process.arguments = ["-" + architecture, helper.path, "--windowed", "--frames", "3"]
        process.environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !["WINE", "CX_", "DXMT_", "DYLD_", "MTL_"].contains(where: key.hasPrefix)
        }
        // Use a file so an unexpected diagnostic flood cannot fill a pipe.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("ow120-metal-" + UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: outputURL) }
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let timedOut = process.isRunning
        if timedOut { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        let output = LogTail.read(outputURL)
        return (!timedOut && process.terminationStatus == 0 && output.contains("METAL_COMMANDS_OK count=3"), timedOut, output)
    }
}

extension EnvironmentService {
    private var systemGraphicsFile: URL { layout.root.appendingPathComponent("Reports/system-graphics.json") }
    public func systemGraphicsResult() -> SystemGraphicsResult? {
        guard let result = try? JSONFile.read(SystemGraphicsResult.self, from: systemGraphicsFile), result.applies(to: SystemGraphicsProbe.bootSession()) else { return nil }
        return result
    }
    @discardableResult public func checkSystemGraphics(helper: URL) throws -> SystemGraphicsResult {
        let result = try SystemGraphicsProbe.run(helper)
        try JSONFile.write(result, to: systemGraphicsFile)
        return result
    }
    func requireSystemGraphics(helper: URL) throws {
        let result = try systemGraphicsResult() ?? checkSystemGraphics(helper: helper)
        if let issue = result.issue { throw OWError.message(issue.title + "。" + issue.detail) }
    }
}
