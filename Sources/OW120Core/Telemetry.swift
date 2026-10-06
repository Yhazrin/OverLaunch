import Foundation

public struct FrameSample: Codable, Sendable {
    public var frame: Int
    public var milliseconds: Double
    public var shaderCompiles: Int
    public var blockedMS: Double
}

public struct FrameMetrics: Codable, Sendable {
    public var frames: Int
    public var seconds: Double
    public var averageFPS: Double
    public var onePercentLow: Double
    public var p99MS: Double
    public var over16MS: Int
    public var over50MS: Int
    public var over100MS: Int
    public var shaderCompiles: Int
    public var compileCorrelatedLongFrames: Int
    public static func calculate(_ samples: [FrameSample]) -> FrameMetrics? {
        let rows = samples.filter { $0.milliseconds.isFinite && $0.milliseconds > 0 }
        guard !rows.isEmpty else { return nil }
        let times = rows.map(\.milliseconds).sorted()
        let total = times.reduce(0, +)
        let tailCount = max(1, Int(ceil(Double(times.count) * 0.01)))
        let tailMean = times.suffix(tailCount).reduce(0, +) / Double(tailCount)
        let p99 = times[max(0, Int(ceil(Double(times.count) * 0.99)) - 1)]
        return FrameMetrics(frames: rows.count, seconds: total / 1000, averageFPS: Double(rows.count) * 1000 / total, onePercentLow: 1000 / tailMean, p99MS: p99, over16MS: times.filter { $0 > 16.667 }.count, over50MS: times.filter { $0 > 50 }.count, over100MS: times.filter { $0 > 100 }.count, shaderCompiles: rows.reduce(0) { $0 + $1.shaderCompiles }, compileCorrelatedLongFrames: rows.filter { $0.milliseconds > 16.667 && $0.shaderCompiles > 0 }.count)
    }
}

public enum FrameCSV {
    public static func parse(_ text: String) -> [FrameSample] {
        // Ignore a partially-written trailing row; the writer flushes every 256 frames.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").dropLast()
        guard let header = lines.first, header.contains("dt_us") else { return [] }
        let names = header.split(separator: ",").map(String.init)
        guard let dtIndex = names.firstIndex(of: "dt_us"), let frameIndex = names.firstIndex(of: "frame") else { return [] }
        return lines.dropFirst().compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == names.count, let dt = Double(fields[dtIndex]), dt.isFinite, dt > 0, let frame = Int(fields[frameIndex]) else { return nil }
            let compiles = names.firstIndex(of: "compiles").flatMap { Int(fields[$0]) } ?? 0
            let block = names.firstIndex(of: "block_us").flatMap { Double(fields[$0]) } ?? 0
            return FrameSample(frame: frame, milliseconds: dt / 1000, shaderCompiles: max(0, compiles), blockedMS: block / 1000)
        }
    }
}

public struct TelemetrySnapshot: Sendable {
    public var session: SessionInfo
    public var metrics: FrameMetrics?
    public var recent: [Double]
    public var totalFrames: Int
    public var status: String
    public var gameRSSMB: Double?
}

/// Reads only newly appended bytes; a long session never reparses the entire CSV each tick.
final class FrameTail {
    let file: URL
    var offset: UInt64 = 0
    var header: String?
    var pending = ""
    var frames: [FrameSample] = []
    init(_ file: URL) { self.file = file }
    func readNewFrames() -> [FrameSample] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return frames }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            if size < offset { offset = 0; header = nil; pending = ""; frames = [] }
            guard size > offset else { return frames }
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data(); offset += UInt64(data.count)
            pending += String(decoding: data, as: UTF8.self)
            // Windows CRT writes CRLF. Swift treats CRLF as one Character, so
            // lastIndex(of: "\n") cannot see it until it is normalized. Normalize
            // after combining chunks so even a split CR/LF pair is handled.
            pending = pending.replacingOccurrences(of: "\r\n", with: "\n")
            guard let newline = pending.lastIndex(of: "\n") else { return frames }
            let complete = String(pending[...newline]); pending = String(pending[pending.index(after: newline)...])
            if header == nil {
                header = complete.components(separatedBy: "\n").first
                frames.append(contentsOf: FrameCSV.parse(complete))
            } else { frames.append(contentsOf: FrameCSV.parse((header ?? "") + "\n" + complete)) }
        } catch { return frames }
        return frames
    }
}

public actor TelemetryService {
    private let environment: EnvironmentService
    private var lastDiscovery = Date.distantPast
    private var readers: [URL: FrameTail] = [:]
    public init(environment: EnvironmentService) { self.environment = environment }
    static func requiresDiscovery(gamePID: Int32?, modified: Date?, now: Date) -> Bool {
        gamePID == nil || modified == nil || now.timeIntervalSince(modified!) > 30
    }
    static func adoptingGamePID(_ pid: Int32?, in original: SessionInfo) -> SessionInfo {
        guard pid != original.gamePID else { return original }
        var session = original
        session.gamePID = pid
        // Frame numbers restart with the game; marks from the old process
        // cannot describe a sample in the new frame stream.
        session.benchmarkStartFrame = nil; session.benchmarkEndFrame = nil
        session.benchmarkStartedAt = nil; session.benchmarkEndedAt = nil
        return session
    }
    public func poll(_ original: SessionInfo) async -> TelemetrySnapshot {
        var session = original
        let now = Date()
        let previousFile = session.gamePID.map { session.folder.appendingPathComponent("frames-\($0).csv") }
        let modified = previousFile.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        if Self.requiresDiscovery(gamePID: session.gamePID, modified: modified, now: now), now.timeIntervalSince(lastDiscovery) >= 10, await environment.active() {
            lastDiscovery = Date()
            // DXMT's Windows CRT getpid() uses the Wine process ID, not the host PID.
            let layout = environment.layout
            let env = await environment.wineEnvironment()
            let tasks = (try? Command.run(layout.engine.appendingPathComponent("bin/wine").path, layout.wineArguments(["tasklist.exe", "/fo", "csv", "/nh"]), environment: env, allowFailure: true)) ?? ""
            var currentPID: Int32?
            for row in tasks.components(separatedBy: .newlines) where row.lowercased().contains("overwatch.exe") {
                let fields = row.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" \r\n")) }
                if fields.count > 1, fields[0].lowercased() == "overwatch.exe", let pid = Int32(fields[1]) { currentPID = pid }
            }
            // A failed query must not erase a finished sample. Only adopt a
            // verified running game; keep the last stream for saved reports.
            if let currentPID, currentPID != session.gamePID {
                session = Self.adoptingGamePID(currentPID, in: session)
                readers.removeAll()
                try? JSONFile.write(session, to: session.folder.appendingPathComponent("session.json"))
            }
        }
        guard let pid = session.gamePID else { return TelemetrySnapshot(session: session, metrics: nil, recent: [], totalFrames: 0, status: "等待进入游戏 · 战网登录与更新由官方客户端处理", gameRSSMB: nil) }
        let file = session.folder.appendingPathComponent("frames-\(pid).csv")
        let reader = readers[file] ?? FrameTail(file)
        readers[file] = reader
        let samples = reader.readNewFrames()
        let measured: [FrameSample]
        if let start = session.benchmarkStartFrame {
            measured = Array(samples.dropFirst(min(start, samples.count)).prefix(max(0, (session.benchmarkEndFrame ?? samples.count) - start)))
        } else { measured = Array(samples.suffix(1200)) }
        let currentModified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let stale = Date().timeIntervalSince(currentModified) > 30
        var status = samples.count < 240 ? "正在等待连续游戏画面" : session.benchmarkStartFrame == nil ? "实时观察 · 进入对局后点击“开始实战采样”" : session.benchmarkEndFrame == nil ? "正在采集实战帧时间" : "实战采样已保存"
        let ps = (try? Command.run("/bin/ps", ["-axo", "rss=,comm="])) ?? ""
        let gameRow = ps.components(separatedBy: .newlines).first { $0.lowercased().contains("overwatch.exe") }
        let rss = gameRow?.split(whereSeparator: \.isWhitespace).first.flatMap { Double($0) }.map { $0 / 1024 }
        if gameRow == nil { status = "游戏已退出" }
        else if stale { status = "游戏暂未输出新画面 · 请检查加载状态或报错窗口" }
        let canDisplay = session.benchmarkEndFrame != nil || (gameRow != nil && !stale && samples.count >= 240)
        return TelemetrySnapshot(session: session, metrics: canDisplay ? FrameMetrics.calculate(measured) : nil, recent: canDisplay ? Array(samples.suffix(180).map(\.milliseconds)) : [], totalFrames: samples.count, status: status, gameRSSMB: rss)
    }
    public func mark(_ session: SessionInfo, start: Bool, totalFrames: Int) throws -> SessionInfo {
        guard session.gamePID != nil, totalFrames >= 240 else { throw OWError.message("尚未获得连续游戏帧记录，请先进入游戏。") }
        var updated = session
        if start {
            updated.benchmarkStartFrame = totalFrames; updated.benchmarkEndFrame = nil
            updated.benchmarkStartedAt = Date(); updated.benchmarkEndedAt = nil
        } else {
            guard updated.benchmarkStartFrame != nil else { throw OWError.message("尚未开始采样。") }
            updated.benchmarkEndFrame = totalFrames; updated.benchmarkEndedAt = Date()
        }
        try JSONFile.write(updated, to: updated.folder.appendingPathComponent("session.json"))
        return updated
    }
    public func exportReport(_ session: SessionInfo) async throws -> URL {
        let snapshot = await poll(session)
        guard let m = snapshot.metrics, snapshot.session.benchmarkStartFrame != nil else { throw OWError.message("请先开始实战采样，再导出报告。") }
        let url = session.folder.appendingPathComponent("性能报告.md")
        let quality = m.seconds >= 60 ? "采样时间达到 60 秒；是否代表团战仍取决于选取的场景。" : "样本不足 60 秒，不足以判断稳定性。"
        let report = """
        OW120 实战采样报告

        目标：\(session.profile.targetFPS) FPS。以下均为实际 DXMT 呈现间隔统计，不是显示器刷新率或输入延迟。

        - 场景：用户手动选取的采样区间
        - 配置：\(session.profile.width)×\(session.profile.height)，\(session.profile.backend.rawValue)，\(session.profile.graphicsAPI)
        - MSync：\(session.profile.msync)，着色器 IR 释放：\(session.profile.releaseShaderIR)
        - 帧数：\(m.frames)，时长：\(String(format: "%.1f", m.seconds)) 秒
        - 平均 FPS：\(String(format: "%.1f", m.averageFPS))
        - 1% low：\(String(format: "%.1f", m.onePercentLow)) FPS
        - P99 帧时间：\(String(format: "%.2f", m.p99MS)) ms
        - >16.7ms / >50ms / >100ms 长帧：\(m.over16MS) / \(m.over50MS) / \(m.over100MS)
        - 编译计数：\(m.shaderCompiles)，伴随编译的 >16.7ms 帧：\(m.compileCorrelatedLongFrames)

        \(quality)

        1% low = 1000 / 最慢 1% 帧的平均耗时(ms)，不等于 1000/P99。加载、切出窗口和菜单如果发生在手动采样区间内，会如实计入。编译与长帧相关不等同于已证明因果。此报告不自动宣称达成稳定 120 FPS。

        原始文件：frames-\(session.gamePID ?? 0).csv。原始启动日志可能含账号相关信息，默认只保存在本机，不上传。
        """
        try Command.write(report, to: url)
        try JSONFile.write(m, to: session.folder.appendingPathComponent("metrics.json"))
        return url
    }
}
