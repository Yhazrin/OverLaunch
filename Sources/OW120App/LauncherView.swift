import SwiftUI
import OW120Core

// Explicit wrapper: the macOS 27 CLT State macro has no bundled plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum LauncherPage: String, CaseIterable {
    case home, picture, performance, appearance, tools
    var title: String {
        switch self { case .home: "开始"; case .picture: "启动设置"; case .performance: "性能"; case .appearance: "外观"; case .tools: "工具箱" }
    }
    var englishTitle: String {
        switch self { case .home: "OVERWATCH"; case .picture: "LAUNCH SETTINGS"; case .performance: "PERFORMANCE"; case .appearance: "HERO GALLERY"; case .tools: "TOOLS" }
    }

}

struct LauncherView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var model = LauncherModel()
    @ViewState private var page = LauncherPage.home
    @ViewState private var showAdvanced = false
    @ViewState private var compact = false
    @ViewState private var heroViewportWidth: CGFloat = 1048
    @ViewState private var heroScrollTarget: String? = "default"
    @ViewState private var customOutput = false
    @ViewState private var selectHost = GameSelectHost()
    private var ready: Bool { model.hasLoaded && model.machine?.prepared == true && model.layout.isSoju }
    private var dirty: Bool { model.profile != model.savedProfile }
    private var sampling: Bool { model.session?.benchmarkStartFrame != nil && model.session?.benchmarkEndFrame == nil }
    private var selectedHero: HeroIcon? { model.iconAssets?.catalog.heroes.first { $0.id == model.appearance.iconID } }
    // The default stage illustration does not change the saved application icon.
    private var featuredHero: HeroIcon? { selectedHero ?? model.iconAssets?.catalog.heroes.first { $0.id == "tracer" } }
    private var stageStatusColor: Color {
        if model.error != nil || model.startupIssue != nil { return LauncherTheme.accent }
        if model.running { return LauncherTheme.cyan }
        return ready ? Color(red: 0.48, green: 0.82, blue: 0.62) : Color.white.opacity(0.55)
    }
    private var checkSummary: String {
        guard !model.checks.isEmpty else { return "正在检查" }
        let count = model.checks.filter { $0.state != .ready }.count
        return count == 0 ? "启动检查通过" : "\(count) 项需查看"
    }
    private var runtimeTitle: String {
        if model.busy { return "正在处理" }
        if !model.hasLoaded { return "正在检查" }
        if model.startupIssue != nil || model.error != nil { return "需要处理" }
        if model.running { return "战网运行中" }
        return ready ? "已就绪" : "待导入"
    }
    private var primaryButtonTitle: String {
        if !model.hasLoaded { return "正在检查…" }
        if model.running { return "战网运行中" }
        return ready ? "启动国服战网" : "导入游戏"
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    navigation
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            alerts
                            if page != .home {
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    GameDisplayText(text: page.englishTitle, size: compact ? 40 : 50)
                                        .accessibilityHidden(true)
                                    Text(page.title).font(LauncherTheme.chineseHeading(32)).accessibilityAddTraits(.isHeader)
                                }
                            }
                            switch page {
                            case .home: homePage
                            case .picture: picturePage
                            case .performance: performancePage
                            case .appearance: appearancePage
                            case .tools: toolsPage
                            }
                        }
                        .id(page).transition(.opacity)
                        .frame(maxWidth: 1120, alignment: .leading)
                        .padding(compact ? 22 : 36)
                        .frame(maxWidth: .infinity, alignment: .top)

                    }.scrollIndicators(.never)
                }
                GameSelectPortalLayer(host: selectHost)
            }
            .coordinateSpace(name: "gameSelectCanvas")
            .background(GeometricBackdrop().accessibilityHidden(true))
            .onChange(of: geometry.size.width, initial: true) { _, width in
                compact = width < 860
                heroViewportWidth = min(1120, width - (compact ? 44 : 72))
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                selectHost.canvasSize = size
                selectHost.dismiss()
            }
            .onChange(of: page) { _, _ in selectHost.dismiss() }
        }
        .ignoresSafeArea(.container, edges: .top)
        .font(LauncherTheme.uiFont(14))
        .foregroundStyle(LauncherTheme.text)
        .frame(minWidth: 660, minHeight: 500)
        .tint(LauncherTheme.blue)
        .buttonStyle(OverButtonStyle())
        .environment(\.gameSelectHost, selectHost)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: page)
        .task { await model.monitorLoop() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.foreground = phase == .active
            if phase != .active { selectHost.dismiss() }
        }
        .confirmationDialog("关闭 OverLaunch 的游戏与战网？", isPresented: $model.showStopConfirmation, titleVisibility: .visible) {
            Button("停止独立环境", role: .destructive) { model.stop() }
        } message: { Text("正在进行的对局会中断。此操作只停止 OverLaunch 的运行环境。") }
        .confirmationDialog("保留当前环境并重新准备？", isPresented: $model.showArchiveConfirmation, titleVisibility: .visible) {
            Button("归档当前环境") { model.archive() }
        } message: { Text("当前运行时、游戏和配置将移到 Archived。原 CrossOver 安装仍可使用。") }
    }
    private var navigation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                OWEmblem().frame(width: 26, height: 26).accessibilityHidden(true)
                GameDisplayText(text: "OVERLAUNCH", size: 28, spacing: 0.6)
                Spacer(minLength: 8)
                if model.busy || !model.hasLoaded { ProgressView().controlSize(.mini).colorScheme(.dark) }
                Text(runtimeTitle).font(LauncherTheme.uiFont( 12, weight: .semibold))
                    .foregroundStyle(model.error == nil && model.startupIssue == nil ? Color.white : Color.orange)
            }.foregroundStyle(Color.white)
                .padding(.leading, 90).padding(.trailing, compact ? 22 : 36).frame(height: 56)
                .background(WindowDragRegion())
            HStack(spacing: -9) {
                ForEach(Array(LauncherPage.allCases.enumerated()), id: \.element.rawValue) { index, item in
                    Button { page = item } label: {
                        GameNavigationTabLabel(title: item.title, selected: page == item)
                    }
                    .buttonStyle(OverNavigationStyle())
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(page == item ? "已选中" : "")
                    .accessibilityIdentifier("nav-\(item.rawValue)")
                    .help("\(item.title) · ⌘\(index + 1)")
                }
            }.padding(.horizontal, compact ? 12 : 26)
        }.background(LauncherTheme.sidebar).clipped()
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { selectHost.topInset = geometry.frame(in: .named("gameSelectCanvas")).maxY + 4 }
                        .onChange(of: geometry.frame(in: .named("gameSelectCanvas"))) { _, frame in selectHost.topInset = frame.maxY + 4 }
                }
            }
    }
    private var alerts: some View {
        VStack(spacing: 12) {
            if let issue = model.startupIssue { notice(issue.title, detail: issue.detail) }
            if let error = model.error { notice("操作未完成", detail: error) }
            if model.busy {
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text(model.status).font(LauncherTheme.uiFont(13, weight: .regular)).textSelection(.enabled) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func notice(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill").font(LauncherTheme.uiFont(15, weight: .semibold))
            Text(detail).font(LauncherTheme.uiFont(13, weight: .regular)).foregroundStyle(LauncherTheme.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if page != .tools { Button("查看工具箱") { page = .tools }.buttonStyle(OverButtonStyle(kind: .quiet)) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(LauncherTheme.surface)
    }
    private var homePage: some View {
        VStack(alignment: .leading, spacing: 28) {
            launchPanel
            if ready { homeLaunchSettings }
            heroRoster
            Divider().overlay(LauncherTheme.rule)
            if compact {
                VStack(alignment: .leading, spacing: 24) { homePerformance; Divider(); deviceInformation }
            } else {
                HStack(alignment: .top, spacing: 44) { homePerformance; deviceInformation }
            }
        }
    }
    private var launchPanel: some View {
        VStack(spacing: 0) {
            LaunchStage(
                compact: compact,
                portrait: featuredHero.flatMap { model.iconAssets?.portrait($0.id) },
                heroTitle: featuredHero?.title ?? "守望先锋",
                heroEnglishName: featuredHero?.englishName ?? "Overwatch",
                status: runtimeTitle,
                statusColor: stageStatusColor,
                machine: model.machine.map { "\($0.chip)  /  \($0.memoryGB) GB" } ?? "Apple Silicon · macOS",
                message: model.busy ? model.status : model.running ? "请在战网内点击“进入游戏”。" :
                    model.sourceBottle.map { "已选择：\($0.lastPathComponent)" } ?? model.status
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Button { ready ? model.launch() : model.prepare() } label: {
                        HStack(spacing: 16) {
                            Text(primaryButtonTitle).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            Image(systemName: ready ? "chevron.forward.2" : "square.and.arrow.down")
                                .font(.system(size: 16, weight: .bold))
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LaunchPrimaryButtonStyle())
                    .frame(maxWidth: 340, alignment: .leading)
                    .disabled(model.busy || model.running || !model.hasLoaded)
                    .accessibilityIdentifier("launchGame")
                    .help(ready ? "打开国服战网，再在战网内进入游戏" : "复制已有游戏并安装免费运行组件")
                    if model.running {
                        Button("停止游戏与战网") { model.showStopConfirmation = true }
                            .buttonStyle(LaunchSecondaryButtonStyle()).disabled(model.busy)
                    } else if model.hasLoaded && !ready {
                        Button("选择已有游戏目录…") { model.chooseBottle() }
                            .buttonStyle(LaunchSecondaryButtonStyle()).disabled(model.busy)
                    }
                }
            }
            if ready {
                LaunchProfileStrip(
                    mode: model.savedProfile.selectedConfigurationMode.title,
                    output: model.savedProfile.borderless && model.savedProfile.disableRetina ? "跟随桌面" : "\(model.savedProfile.width) × \(model.savedProfile.height)",
                    render: "\(model.savedProfile.effectiveRenderScale)%",
                    target: "\(model.savedProfile.targetFPS) FPS"
                )
            } else if model.hasLoaded {
                Text("首次下载运行组件约 367 MB").font(LauncherTheme.uiFont(12))
                    .foregroundStyle(LauncherTheme.muted).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var homeLaunchSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("启动设置").font(LauncherTheme.chineseHeading(22)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("全部设置") { page = .picture }.buttonStyle(OverButtonStyle(kind: .quiet))
                Button(dirty ? "保存设置" : "已保存") { model.saveProfile() }
                    .disabled(model.busy || !model.hasLoaded || !dirty).accessibilityIdentifier("saveLaunchResolution")
            }
            VStack(spacing: 5) { configurationPicker; resolutionPicker; renderScalePicker }
            if model.running || dirty {
                Text(dirty ? "未保存 · 下次启动生效" : "下次启动生效")
                    .font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted)
            }
        }
    }
    private var homePerformance: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("性能记录", action: "查看", destination: .performance)
            if let metrics = model.snapshot?.metrics {
                infoRow("平均帧率", value: String(format: "%.1f FPS", metrics.averageFPS))
                infoRow("1% low", value: String(format: "%.1f FPS", metrics.onePercentLow))
                infoRow("P99 帧时间", value: String(format: "%.2f ms", metrics.p99MS))
            } else {
                Text("暂无连续帧记录").font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var deviceInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("设备信息", action: "检查", destination: .tools)
            infoRow("运行环境", value: ready ? "独立免费引擎" : "待准备")
            infoRow("启动检查", value: checkSummary)
            if let machine = model.machine {
                infoRow("屏幕刷新率", value: machine.displayHz > 0 ? "\(Int(machine.displayHz.rounded())) Hz" : "动态刷新率")
                if machine.lowPowerMode { Label("低电量模式已开启", systemImage: "battery.25percent").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.accent) }
                if machine.maximumDisplayHz > 0 && machine.maximumDisplayHz < 119 {
                    Text("此屏幕最高 \(Int(machine.maximumDisplayHz.rounded())) Hz，无法显示完整的 120 Hz 刷新。").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
                }
            }
            Button("打开 Mac 显示设置") { model.showDisplaySettings() }.buttonStyle(OverButtonStyle(kind: .quiet)).font(LauncherTheme.uiFont(12, weight: .regular))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heroRoster: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("应用外观").font(LauncherTheme.chineseHeading(22)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { browseHeroes(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(heroRosterIndex == 0)
                    .accessibilityLabel("向左浏览英雄").accessibilityIdentifier("browseHeroesLeft")
                Button { browseHeroes(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(heroRosterIndex >= heroRosterLastPage)
                    .accessibilityLabel("向右浏览英雄").accessibilityIdentifier("browseHeroesRight")
                Button("全部英雄") { page = .appearance }.buttonStyle(OverButtonStyle(kind: .quiet))
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    homeHeroCard(nil)
                    ForEach(model.iconAssets?.catalog.heroes ?? []) { hero in homeHeroCard(hero) }
                }.scrollTargetLayout().padding(.horizontal, 4).padding(.vertical, 5)
            }.scrollIndicators(.never).scrollPosition(id: $heroScrollTarget, anchor: .leading)
        }
    }
    private var heroRosterIDs: [String] { ["default"] + (model.iconAssets?.catalog.heroes.map(\.id) ?? []) }
    private var heroRosterIndex: Int { heroRosterIDs.firstIndex(of: heroScrollTarget ?? "default") ?? 0 }
    private var heroRosterLastPage: Int { max(0, heroRosterIDs.count - max(1, Int((heroViewportWidth - 8) / 100))) }
    private func browseHeroes(_ direction: Int) {
        let next = min(heroRosterLastPage, max(0, heroRosterIndex + direction * (compact ? 4 : 8)))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) { heroScrollTarget = heroRosterIDs[next] }
    }
    private func homeHeroCard(_ hero: HeroIcon?) -> some View {
        let id = hero?.id ?? "default"
        return LaunchHeroCard(portrait: hero.flatMap { model.iconAssets?.portrait($0.id) },
                              title: hero?.title ?? "默认 OW 标志", englishName: hero?.englishName ?? "Overwatch",
                              selected: model.appearance.iconID == id) { model.selectIcon(id) }
            .accessibilityIdentifier("hero-icon-\(id)")
            .id(id)
    }
    private func heroTile(_ hero: HeroIcon?, size: CGFloat) -> some View {
        let id = hero?.id ?? "default"
        let selected = model.appearance.iconID == id
        return Button { model.selectIcon(id) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Rectangle().fill(LauncherTheme.sidebar.opacity(0.88))
                    if let hero, let image = model.iconAssets?.portrait(hero.id) {
                        Image(nsImage: image).resizable().scaledToFit().padding(2)
                    } else { OWEmblem().padding(10) }
                }
                .frame(width: size, height: size)
                .overlay(Rectangle().strokeBorder(selected ? LauncherTheme.accent : Color.white.opacity(0.8), lineWidth: selected ? 3 : 1))
                .overlay(alignment: .bottomTrailing) {
                    if selected { Rectangle().fill(LauncherTheme.accent).frame(width: 14, height: 5).padding(3) }
                }
                if size > 58 {
                    GameDisplayText(text: hero?.englishName.uppercased() ?? "OVERWATCH", size: 17, spacing: 0.2)
                        .lineLimit(1).minimumScaleFactor(0.7).frame(width: size + 10)
                    Text(hero?.title ?? "默认 OW").font(LauncherTheme.chineseHeading(16))
                        .lineLimit(1).minimumScaleFactor(0.8).frame(width: size + 10)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(HeroTileStyle(selected: selected))
        .accessibilityLabel(hero?.title ?? "默认 OW 标志")
        .accessibilityValue(selected ? "已选择应用图标" : "")
        .accessibilityIdentifier("hero-icon-\(id)")
        .help("应用图标：\(hero?.title ?? "默认 OW 标志")")
    }
    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 22) {
                if let icon = model.iconAssets?.icon(model.appearance.iconID) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 90, height: 90)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedHero?.title ?? "默认 OW 标志").font(LauncherTheme.chineseHeading(28))
                    Text(model.appearanceStatus).font(LauncherTheme.uiFont(13, weight: .regular)).foregroundStyle(LauncherTheme.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Dock 图标 · 应用台使用默认标志").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
                }
                Spacer(minLength: 0)
            }
            HStack {
                GameSearchField(text: $model.heroSearch).frame(maxWidth: 360)
                    .accessibilityIdentifier("heroSearch")
                Spacer(minLength: 0)
                Button("恢复默认") { model.selectIcon("default") }.disabled(model.appearance.iconID == "default")
                    .accessibilityIdentifier("restoreDefaultIcon")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82, maximum: 104), spacing: 16)], alignment: .leading, spacing: 20) {
                if model.heroSearch.isEmpty { heroTile(nil, size: 72) }
                ForEach(filteredHeroes) { hero in heroTile(hero, size: 72) }
            }
            if filteredHeroes.isEmpty && !model.heroSearch.isEmpty { Text("未找到英雄").foregroundStyle(LauncherTheme.muted) }
            Divider().overlay(LauncherTheme.rule)
            Text("\(model.iconAssets?.catalog.heroes.count ?? 0) 个图标").font(LauncherTheme.uiFont(13, weight: .regular))
            Text("素材：Blizzard Entertainment · 社区图标")
                .font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted).fixedSize(horizontal: false, vertical: true)
            Link("图标资源：overwatch-hero-icons", destination: URL(string: "https://github.com/drippinghere/overwatch-hero-icons")!).font(LauncherTheme.uiFont(12, weight: .regular))
        }
    }
    private var filteredHeroes: [HeroIcon] {
        let query = model.heroSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return (model.iconAssets?.catalog.heroes ?? []).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.englishName.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }
    private var outputID: String {
        if model.profile.borderless && model.profile.disableRetina { return "desktop" }
        let id = "\(model.profile.width)x\(model.profile.height)"
        return customOutput || !OutputResolution.presets.contains(where: { $0.id == id }) ? "custom" : id
    }
    private func profileBinding<Value>(_ path: WritableKeyPath<GameProfile, Value>) -> Binding<Value> {
        Binding(get: { model.profile[keyPath: path] }, set: { value in model.editProfile { $0[keyPath: path] = value } })
    }
    private var configurationPicker: some View {
        GameSelect(title: "配置模式", selection: Binding(get: { model.profile.selectedConfigurationMode }, set: {
            model.selectConfigurationMode($0); customOutput = false
        }), choices: ConfigurationMode.allCases.map { GameChoice($0, $0.title) }, compact: compact)
            .disabled(model.busy || !model.hasLoaded).accessibilityIdentifier("configurationMode")
    }
    private var resolutionPicker: some View {
        let choices = [GameChoice("desktop", "跟随桌面 · 无边框")]
            + OutputResolution.presets.sorted { $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width }.map { GameChoice($0.id, $0.title) }
            + [GameChoice("custom", "自定义尺寸")]
        return GameSelect(title: "输出分辨率", selection: Binding(get: { outputID }, set: { id in
            customOutput = id == "custom"
            model.editProfile { profile in
                if id == "desktop" { profile.borderless = true; profile.disableRetina = true }
                else if let resolution = OutputResolution.presets.first(where: { $0.id == id }) { profile = resolution.applying(to: profile) }
                else { profile = profile.withFixedOutput(width: profile.width, height: profile.height) }
            }
        }), choices: choices, compact: compact)
            .disabled(model.busy || !model.hasLoaded).accessibilityIdentifier("launchResolution")
    }
    private var renderScalePicker: some View {
        let values = Array(Set([50, 60, 67, 75, 80, 90, 100, model.profile.effectiveRenderScale])).sorted(by: >)
        return GameSelect(title: "渲染比例", selection: Binding(get: { model.profile.effectiveRenderScale }, set: { value in
            model.editProfile { $0.renderScalePercent = value }
        }), choices: values.map { GameChoice($0, "\($0)%") }, compact: compact)
            .disabled(model.busy || !model.hasLoaded).accessibilityIdentifier("launchRenderScale")
    }
    private func sectionHeading(_ title: String, action: String, destination: LauncherPage) -> some View {
        HStack {
            Text(title).font(LauncherTheme.chineseHeading(22)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action) { page = destination }.buttonStyle(OverButtonStyle(kind: .quiet)).font(LauncherTheme.uiFont(12, weight: .regular))
        }
    }
    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(LauncherTheme.muted)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }.font(LauncherTheme.uiFont( 13)).accessibilityElement(children: .combine)
    }
    private var picturePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let machine = model.machine {
                Text("\(machine.chip) · \(machine.memoryGB) GB · \(machine.desktopWidth ?? model.profile.width) × \(machine.desktopHeight ?? model.profile.height)")
                    .font(LauncherTheme.uiFont( 13)).foregroundStyle(LauncherTheme.muted)
            }
            VStack(spacing: 5) {
                configurationPicker
                resolutionPicker
                if outputID == "custom" {
                    HStack(spacing: 14) {
                        GameNumberField(title: "宽度", value: Binding(get: { model.profile.width }, set: { value in model.editProfile { $0.width = value } }))
                        Text("×").foregroundStyle(LauncherTheme.muted)
                        GameNumberField(title: "高度", value: Binding(get: { model.profile.height }, set: { value in model.editProfile { $0.height = value } }))
                    }.padding(.vertical, 7).disabled(model.busy || !model.hasLoaded)
                    Text("宽 640–8192，高 480–8192").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
                }
                renderScalePicker
                GameRange(title: "自定义渲染比例", value: Binding(get: { model.profile.effectiveRenderScale }, set: { value in model.editProfile { $0.renderScalePercent = value } }))
                    .disabled(model.busy || !model.hasLoaded).accessibilityIdentifier("renderScaleSlider")
                GameSelect(title: "帧率限制", selection: profileBinding(\.targetFPS), choices: [120, 144, 165, 240].map { GameChoice($0, "\($0) FPS") }, compact: compact)
                    .disabled(model.busy || !model.hasLoaded).accessibilityIdentifier("frameRateLimit")
            }
            HStack {
                Text(model.profile.selectedConfigurationMode == .manual ? "手动设置" : "按设备和显示器匹配")
                Spacer()
                Text(model.profile.borderless ? "无边框" : "窗口")
            }.font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
            Button { showAdvanced.toggle() } label: {
                HStack { Text("高级设置"); Spacer(); Image(systemName: showAdvanced ? "chevron.up" : "chevron.down") }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("advancedSettings")
            if showAdvanced {
                VStack(spacing: 5) {
                    settingToggle("MSync 同步", detail: "协调游戏线程。", value: profileBinding(\.msync))
                    settingToggle("Metal 帧率同步", detail: "关闭后使用游戏限帧。", value: Binding(get: { model.profile.usesMetalFramePacing }, set: { value in model.editProfile { $0.metalFramePacing = value } }))
                    settingToggle("节省内存", detail: "释放着色器中间数据，可能增加重复编译。", value: profileBinding(\.releaseShaderIR))
                    settingToggle("性能叠层", detail: "显示 Metal 图形性能数据。", value: profileBinding(\.showHUD))
                    GameSelect(title: "显存上报", selection: profileBinding(\.videoMemoryMB), choices: [0, 4096, 6144, 8192, 10240, 12288, 16384, 24576].map { GameChoice($0, $0 == 0 ? "自动" : "\($0 / 1024) GB") }, compact: compact)
                        .help("兼容层向游戏上报的显存值，不是独立显卡内存。")
                }.disabled(model.busy || !model.hasLoaded).transition(.opacity)
            }
            HStack(spacing: 12) {
                Button("保存设置") { model.saveProfile() }.buttonStyle(OverButtonStyle(kind: .primary))
                    .disabled(model.busy || !model.hasLoaded || !dirty).accessibilityIdentifier("saveProfile")
                Button("撤销修改") { model.discardProfileChanges(); customOutput = false }.buttonStyle(OverButtonStyle(kind: .quiet)).disabled(!dirty || model.busy)
                Spacer(minLength: 0)
                Text(dirty ? "未保存" : "已保存").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
            }
            if model.running { Text("下次启动生效").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted) }
            Divider().overlay(LauncherTheme.rule).padding(.top, 14)
            SoftwareInfoView()
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: showAdvanced)
    }
    private func barHeading(_ title: String) -> some View {
        Text(title).font(LauncherTheme.uiFont( 14, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).background(LauncherTheme.sidebar.opacity(0.78))
            .accessibilityAddTraits(.isHeader)
    }
    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        GameToggle(title: title, value: value, compact: compact).help(detail)
    }
    private var performancePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 22) {
                metric("平均帧率", value: model.snapshot?.metrics.map { String(format: "%.1f", $0.averageFPS) } ?? "—", unit: "FPS")
                metric("1% low", value: model.snapshot?.metrics.map { String(format: "%.1f", $0.onePercentLow) } ?? "—", unit: "FPS")
                metric("P99 帧时间", value: model.snapshot?.metrics.map { String(format: "%.2f", $0.p99MS) } ?? "—", unit: "ms")
            }
            VStack(alignment: .leading, spacing: 18) {
                barHeading("帧时间")
                FrameChart(samples: model.snapshot?.recent ?? [], accent: LauncherTheme.blue).frame(height: compact ? 150 : 200)
                HStack {
                    Label("8.33 ms · 120 FPS", systemImage: "minus").foregroundStyle(LauncherTheme.blue)
                    Spacer(minLength: 8)
                    Text("长帧 > 50 ms：\(model.snapshot?.metrics.map { String($0.over50MS) } ?? "—")")
                }.font(LauncherTheme.uiFont(12, weight: .regular))
                Text(model.snapshot?.status ?? "在战网中进入游戏后，这里会显示连续帧记录。")
                    .font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            barHeading("采样与报告")
            Text("采样时保持游戏在前台").font(LauncherTheme.uiFont(13, weight: .regular)).foregroundStyle(LauncherTheme.muted)
            HStack(spacing: 12) {
                Button(sampling ? "结束采样" : "开始采样", systemImage: sampling ? "stop.fill" : "record.circle") { model.markSample(start: !sampling) }
                    .buttonStyle(OverButtonStyle(kind: .primary)).controlSize(.large).disabled(model.busy || model.snapshot?.metrics == nil || !model.running)
                Button("导出报告", systemImage: "square.and.arrow.up") { model.report() }.controlSize(.large)
                    .disabled(model.busy || model.session?.benchmarkStartFrame == nil || sampling)
                if sampling { Label("正在采样", systemImage: "record.circle").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.accent) }
            }
            Text("采样结果包含游戏加载与菜单停顿。").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
        }
    }
    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LauncherTheme.uiFont( 13)).foregroundStyle(LauncherTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(LauncherTheme.heading(compact ? 30 : 40)).monospacedDigit()
                Text(unit).font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var toolsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("启动检查").font(LauncherTheme.uiFont(15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("重新检查", systemImage: "arrow.clockwise") { model.checkHealth() }.controlSize(.large)
                    .disabled(model.busy || !model.hasLoaded || model.running).help("关闭游戏与战网后复测系统图形")
            }
            ForEach(model.checks) { check in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Image(systemName: check.state == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(check.state == .ready ? LauncherTheme.success : LauncherTheme.accent)
                        Text(check.title).font(LauncherTheme.uiFont( 14, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(check.state == .ready ? "通过" : check.state == .attention ? "需查看" : "未就绪").font(LauncherTheme.uiFont(12, weight: .regular)).foregroundStyle(LauncherTheme.muted)
                    }
                    Text(check.detail).font(LauncherTheme.uiFont( 12)).foregroundStyle(LauncherTheme.muted).fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine)
                Divider().overlay(LauncherTheme.rule)
            }
            toolRow("修复运行组件", detail: "保留游戏安装，重新校验引擎与图形组件。") {
                Button("修复组件") { model.repairRuntime() }.disabled(model.running || model.busy || !model.hasLoaded)
            }
            toolRow("本机诊断报告", detail: "保存环境检查结果，帮助定位启动问题。") {
                Button("保存报告") { model.diagnostics() }.disabled(model.busy || !model.hasLoaded)
            }
            toolRow("运行文件", detail: "查看本机日志、配置和性能采样。") {
                Button("打开文件夹") { model.showFiles() }.disabled(!model.hasLoaded)
            }
        }
    }
    private func toolRow<Action: View>(_ title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(LauncherTheme.uiFont( 14, weight: .semibold))
                Text(detail).font(LauncherTheme.uiFont( 12)).foregroundStyle(LauncherTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action().controlSize(.large)
        }
    }
}

private struct GeometricBackdrop: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LauncherTheme.background))
            for i in 0..<7 {
                let x = CGFloat(i) * size.width / 5 - size.width / 5
                let y = i.isMultiple(of: 2) ? size.height * 0.12 : size.height * 0.72
                var triangle = Path(); triangle.move(to: CGPoint(x: x, y: y - size.height * 0.30))
                triangle.addLine(to: CGPoint(x: x + size.width * 0.46, y: y)); triangle.addLine(to: CGPoint(x: x + size.width * 0.16, y: y + size.height * 0.44)); triangle.closeSubpath()
                context.fill(triangle, with: .color(i.isMultiple(of: 2) ? Color.white.opacity(0.07) : LauncherTheme.blue.opacity(0.025)))
            }
        }
    }
}
struct FrameChart: View {
    let samples: [Double]
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let ceiling = max(25.0, min(100.0, samples.max() ?? 25))
            func y(_ value: Double) -> CGFloat { size.height * (1 - min(value, ceiling) / ceiling) }
            for value in [8.333, 16.667] {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y(value))); line.addLine(to: CGPoint(x: size.width, y: y(value)))
                context.stroke(line, with: .color(value < 9 ? accent.opacity(0.4) : LauncherTheme.rule), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            guard samples.count > 1 else {
                context.draw(Text("等待连续游戏帧记录").font(LauncherTheme.uiFont( 13)).foregroundColor(LauncherTheme.muted), at: CGPoint(x: size.width / 2, y: size.height / 2)); return
            }
            var path = Path()
            for (i, value) in samples.enumerated() {
                let point = CGPoint(x: Double(i) / Double(samples.count - 1) * size.width, y: y(value))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }.accessibilityLabel("游戏帧时间曲线，目标 8.33 毫秒；超过 100 毫秒的长帧显示在图表顶部")
    }
}
