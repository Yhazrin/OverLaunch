import SwiftUI
import Observation
import OW120Core

@MainActor @Observable
final class LauncherModel {
    let layout: OW120Core.Layout
    let environment: EnvironmentService
    let telemetry: TelemetryService
    var machine: MachineInfo?
    var profile = GameProfile()
    var savedProfile = GameProfile()
    var hasLoaded = false
    var session: SessionInfo?
    var snapshot: TelemetrySnapshot?
    var busy = false
    var running = false
    var status = "正在检查游戏环境…"
    var error: String?
    var checks: [HealthCheck] = []
    var startupIssue: StartupIssue?
    var sourceBottle: URL?
    var showStopConfirmation = false
    var showArchiveConfirmation = false
    var appearance = LauncherAppearance()
    var iconAssets: AppAppearance?
    var appearanceStatus = ""
    var heroSearch = ""
    var foreground = true
    var setupVisible = false
    var setupStep = SetupStep.device
    var setupDevice: SetupDeviceReport?
    var importAssessment: ImportAssessment?
    private var setupDecisionMade = false
    init(layout: OW120Core.Layout = ProcessInfo.processInfo.environment["OW120_ROOT"].map { Layout(root: URL(fileURLWithPath: $0)) } ?? Layout()) {
        self.layout = layout
        let service = EnvironmentService(layout: layout); environment = service; telemetry = TelemetryService(environment: service)
    }
    func refresh() async {
        if iconAssets == nil {
            do {
                let assets = try AppAppearance()
                iconAssets = assets
                appearance = AppearanceStore(root: layout.root).load(catalog: assets.catalog)
                try assets.apply(appearance)
            } catch { appearanceStatus = error.localizedDescription }
        }
        machine = await environment.inspect(); profile = await environment.launchProfile()
        savedProfile = profile
        running = await environment.active()
        session = await environment.latestSession()
        checks = await environment.healthChecks()
        startupIssue = await environment.startupIssue()
        status = running ? "战网运行中 · 请在战网内进入游戏" : machine?.prepared == true && layout.isSoju ? "独立环境已就绪" : "导入已有游戏后即可启动"
        hasLoaded = true
        if !setupDecisionMade {
            setupDecisionMade = true
            if machine?.prepared != true || !layout.isSoju {
                sourceBottle = machine?.sourceBottle.map { URL(fileURLWithPath: $0) }
                if !FileManager.default.fileExists(atPath: setupDismissal.path) { openSetup() }
            }
        }
    }
    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        Task { defer { busy = false }; do { try await action() } catch { self.error = error.localizedDescription; status = "操作未完成" } }
    }
    func prepare() {
        perform {
            try await self.environment.prepareFreeRuntime(archive: Assets.archive, sourceBottle: self.sourceBottle) { message in Task { @MainActor in self.status = message } }
            await self.refresh()
        }
    }
    private var setupDismissal: URL { layout.root.appendingPathComponent("setup-guide-dismissed") }
    func openSetup() {
        setupVisible = true
        setupStep = machine?.prepared == true && layout.isSoju ? .done : .device
        Task { setupDevice = await environment.setupDeviceReport(); assessSource() }
    }
    func dismissSetup() {
        guard !busy else { return }
        setupVisible = false
        try? Command.write("1\n", to: setupDismissal)
    }
    func assessSource() {
        importAssessment = ImportAssessment.inspect(sourceBottle, destination: layout.root)
        if importAssessment?.canProceed == true { sourceBottle = importAssessment?.source }
    }
    func guidedInstall() {
        guard setupDevice?.canProceed == true else { error = "请先完成设备检查。"; setupStep = .device; return }
        assessSource()
        guard importAssessment?.canProceed == true else { error = importAssessment?.issue; setupStep = .source; return }
        setupStep = .install
        perform {
            try await self.environment.saveLaunchProfile(self.profile)
            try await self.environment.prepareFreeRuntime(archive: Assets.archive, sourceBottle: self.sourceBottle) { message in
                Task { @MainActor in self.status = message }
            }
            await self.refresh()
            self.setupStep = .done
        }
    }
    func launch() {
        perform {
            self.status = "正在检查系统图形并启动…"
            let pendingProfile = self.profile
            let hadUnsavedChanges = pendingProfile != self.savedProfile
            self.session = try await self.environment.launch(selectedProfile: self.savedProfile, graphicsProbe: Assets.graphicsProbe); self.snapshot = nil
            self.savedProfile = await self.environment.launchProfile()
            self.profile = hadUnsavedChanges ? pendingProfile : self.savedProfile
            self.startupIssue = nil
            self.running = true; self.status = "正在打开国服战网…"
        }
    }
    func saveProfile() { perform { try await self.environment.saveLaunchProfile(self.profile); self.profile = await self.environment.launchProfile(); self.savedProfile = self.profile; self.status = "启动配置已保存，下次启动生效" } }
    func discardProfileChanges() { profile = savedProfile }
    func selectIcon(_ id: String) {
        guard let assets = iconAssets, assets.catalog.contains(id) else { return }
        let selected = LauncherAppearance(iconID: id)
        do {
            try assets.apply(selected)
            try AppearanceStore(root: layout.root).save(selected, catalog: assets.catalog)
            appearance = selected
            appearanceStatus = "已保存 · \(id == "default" ? "默认 OW 标志" : assets.catalog.heroes.first { $0.id == id }?.title ?? id)"
        } catch { appearanceStatus = error.localizedDescription }
    }
    func useDeviceRecommendation() {
        selectConfigurationMode(.automatic)
    }
    func selectConfigurationMode(_ mode: ConfigurationMode) {
        guard let machine else { return }
        profile = LaunchConfiguration.match(mode, machine: machine, current: profile)
        profile.configurationMode = mode
        status = "\(mode.title) · 未保存"
    }
    func editProfile(_ edit: (inout GameProfile) -> Void) {
        edit(&profile)
        profile.configurationMode = .manual
    }
    func repairRuntime() {
        perform {
            try await self.environment.prepareFreeRuntime(archive: Assets.archive, repair: true) { message in Task { @MainActor in self.status = message } }
            await self.refresh()
        }
    }
    func stop() { perform { try await self.environment.stop(); self.running = false; self.status = "独立环境已停止" } }
    func archive() {
        perform { let path = try await self.environment.archiveEnvironment(); await self.refresh(); self.status = "旧环境已保留在 Archived，可重新准备。"; NSWorkspace.shared.open(path) }
    }
    func markSample(start: Bool) {
        guard let snapshot else { return }
        perform { self.session = try await self.telemetry.mark(snapshot.session, start: start, totalFrames: snapshot.totalFrames) }
    }
    func report() {
        guard let session else { return }
        perform { let url = try await self.telemetry.exportReport(session); NSWorkspace.shared.open(url) }
    }
    func monitorLoop() async {
        await refresh()
        while !Task.isCancelled {
            if !busy {
                if let assets = iconAssets {
                    let saved = AppearanceStore(root: layout.root).load(catalog: assets.catalog)
                    if saved != appearance {
                        do { try assets.apply(saved); appearance = saved }
                        catch { appearanceStatus = error.localizedDescription }
                    }
                }
                // Adopt CLI-started sessions and externally written sample marks.
                if let latest = await environment.latestSession() { session = latest }
                let wasRunning = running
                running = await environment.active()
                if wasRunning && !running { status = "战网已退出 · 可以重新启动" }
                if foreground, let session, running || session.gamePID != nil {
                    let value = await telemetry.poll(session)
                    snapshot = value; self.session = value.session
                }
                if running { startupIssue = await environment.startupIssue() }
            }
            try? await Task.sleep(for: .seconds(foreground ? 3 : 10))
        }
    }
    func chooseBottle() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "选择已安装国服战网和守望先锋的容器目录（包含 drive_c）"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        if panel.runModal() == .OK { sourceBottle = panel.url; assessSource() }
    }
    func showFiles() { NSWorkspace.shared.open(session?.folder ?? layout.root) }
    func checkHealth() { perform {
        self.status = "正在检查系统图形环境…"
        try await self.environment.checkSystemGraphics(helper: Assets.graphicsProbe)
        self.checks = await self.environment.healthChecks(); self.startupIssue = await self.environment.startupIssue(); self.status = "启动检查已完成"
    } }
    func diagnostics() { perform { let file = try await self.environment.exportDiagnostics(); NSWorkspace.shared.open(file) } }
    func showDisplaySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
}
