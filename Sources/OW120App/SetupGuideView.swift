import SwiftUI
import OW120Core

enum SetupStep: Int, CaseIterable {
    case device, source, profile, install, client, done
    var title: String { ["检查设备", "安装方式", "启动设置", "安装组件", "安装战网", "进入游戏"][rawValue] }
}

struct SetupGuideView<Settings: View>: View {
    @Bindable var model: LauncherModel
    let compact: Bool
    @ViewBuilder var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("安装引导").font(LauncherTheme.chineseHeading(compact ? 30 : 38)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(model.setupStep == .done ? "进入启动台" : "稍后设置") { model.dismissSetup() }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(model.busy)
            }
            HStack(spacing: 5) {
                ForEach(Array(SetupStep.allCases.prefix(4)), id: \.rawValue) { step in
                    HStack(spacing: 6) {
                        Text("\(step.rawValue + 1)").font(LauncherTheme.uiFont(12, weight: .bold))
                        Text(step.title).font(LauncherTheme.uiFont(compact ? 11 : 13, weight: .semibold)).lineLimit(1)
                    }.padding(.vertical, 12).frame(maxWidth: .infinity)
                        .foregroundStyle(step.rawValue == min(3, model.setupStep.rawValue) ? Color.white : LauncherTheme.muted)
                        .background(step.rawValue == min(3, model.setupStep.rawValue) ? LauncherTheme.blue : LauncherTheme.surface.opacity(0.65), in: SlantedPanel())
                }
            }.accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 18) {
                Text(model.setupStep.title).font(LauncherTheme.chineseHeading(26)).accessibilityAddTraits(.isHeader)
                switch model.setupStep {
                case .device: device
                case .source: source
                case .profile:
                    settings
                    Text("设置会保存到独立环境。安装后仍可手动调整；目标帧率不等于实测帧率。")
                        .font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted)
                case .install: install
                case .client: client
                case .done: complete
                }
            }.padding(compact ? 20 : 28).frame(maxWidth: .infinity, alignment: .leading).background(LauncherTheme.surface.opacity(0.65))
            controls
        }.accessibilityIdentifier("setupGuide")
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 14) {
            detail("设备", model.machine.map { "\($0.chip) · \($0.memoryGB) GB" } ?? "正在检查…")
            detail("系统", model.machine?.macOS ?? "正在检查…")
            detail("支持平台", "Apple Silicon · macOS 14+")
            detail("Rosetta 2", model.setupDevice.map { $0.rosettaReady ? "已就绪" : "需要安装" } ?? "正在检查…")
            if let free = model.setupDevice?.availableGB { detail("磁盘可用空间", "\(free) GB") }
            if model.setupDevice?.supported == false { Text("此设备不在当前支持范围内。").foregroundStyle(LauncherTheme.accent) }
            if model.setupDevice?.rosettaReady == false {
                Link("查看 Apple 的 Rosetta 安装说明", destination: URL(string: "https://support.apple.com/zh-cn/102527")!)
                Button("重新检查") { model.openSetup() }.buttonStyle(OverButtonStyle(kind: .quiet))
            }
            if let free = model.setupDevice?.availableGB, free < 5 {
                Text("运行组件需要额外空间，建议清理磁盘后继续。").foregroundStyle(LauncherTheme.accent)
            }
            Text("支持从零安装国服战网，也可以导入已有游戏。运行组件由应用下载，不需要商业 CrossOver 授权。")
                .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
        }.font(LauncherTheme.uiFont(13))
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("安装方式", selection: $model.freshInstall) {
                Text("全新安装战网与游戏").tag(true)
                Text("导入已有游戏容器").tag(false)
            }.pickerStyle(.radioGroup)
            if model.freshInstall {
                Text("创建独立 Windows 环境，下载并打开官方国服战网安装器；登录后在战网内下载守望先锋，无需已有容器或 CrossOver。请预留游戏及更新所需空间。")
                    .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
            } else {
            Text("选择包含 drive_c 的完整容器；也可以直接选择其中的 drive_c 文件夹。")
                .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
            HStack {
                Text(model.sourceBottle?.lastPathComponent ?? "尚未选择").font(LauncherTheme.uiFont(17, weight: .semibold))
                Spacer(minLength: 8)
                Button("选择游戏目录…") { model.chooseBottle() }.buttonStyle(OverButtonStyle())
            }
            if let selection = model.sourceBottle { Text(selection.path).font(LauncherTheme.uiFont(12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if let assessment = model.importAssessment {
                Label(assessment.issue ?? "已找到战网和游戏，可以导入。", systemImage: assessment.canProceed ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(LauncherTheme.uiFont(13)).foregroundStyle(assessment.canProceed ? LauncherTheme.text : LauncherTheme.accent)
            }
            Text("导入前退出源容器中的游戏和战网。原安装保留，游戏、运行组件与 Documents 在 OverLaunch 中分别隔离。")
                .font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted)
            }
        }
    }
    private var install: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.freshInstall ? "首次下载运行组件约 367 MB；下一步下载官方战网安装器，游戏在战网内安装。" : "首次下载运行组件约 367 MB；游戏从本机容器导入。")
            Text(model.freshInstall ? "下载与校验 → 创建独立环境 → 安装图形组件 → 安装战网" : "下载与校验 → 导入游戏 → 安装图形组件 → 检查 Windows 启动能力")
                .foregroundStyle(LauncherTheme.muted)
            if model.busy {
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text(model.status).fixedSize(horizontal: false, vertical: true) }
            } else if model.error == nil { Text("点击“开始安装”准备独立环境。") }
            else { Text("安装未完成，可以重试。现有源容器仍然保留。").foregroundStyle(LauncherTheme.accent) }
        }.font(LauncherTheme.uiFont(13))
    }
    private var client: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("下载官方国服战网安装器，在弹出的窗口中完成安装并保留默认路径。登录、验证码、许可确认和游戏安装均由你在官方战网中完成。")
            Text("1. 下载并运行安装器 → 2. 完成战网安装 → 3. 返回检查 → 4. 登录战网安装守望先锋")
                .foregroundStyle(LauncherTheme.muted)
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status).textSelection(.enabled)
            Button("下载并运行战网安装器") { model.installBattleNet() }
                .buttonStyle(OverButtonStyle(kind: .primary)).disabled(model.busy || model.running)
            Button("检查战网安装结果") { model.checkBattleNetInstallation() }
                .buttonStyle(OverButtonStyle()).disabled(model.busy)
            if model.running {
                Button("停止安装器与战网后重试") { model.showStopConfirmation = true }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(model.busy)
            }
            Text("下载或安装失败可停止后重试；已创建的独立环境会保留。关闭应用后可从工具箱重新打开安装引导。")
                .foregroundStyle(LauncherTheme.muted)
        }.font(LauncherTheme.uiFont(13))
    }
    private var complete: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("独立环境已就绪", systemImage: "checkmark.circle.fill").font(LauncherTheme.uiFont(18, weight: .semibold))
            LaunchProfileStrip(mode: model.savedProfile.selectedConfigurationMode.title,
                               output: model.savedProfile.borderless && model.savedProfile.disableRetina ? "跟随桌面" : "\(model.savedProfile.width) × \(model.savedProfile.height)",
                               render: "\(model.savedProfile.effectiveRenderScale)%", target: "\(model.savedProfile.targetFPS) FPS")
            Text("打开国服战网并登录，选择守望先锋，完成安装或更新，再点击“进入游戏”。游戏请保留默认安装路径。启动时会检查系统图形环境。")
                .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
            Button("打开国服战网") { model.dismissSetup(); model.launch() }
                .buttonStyle(OverButtonStyle(kind: .primary)).disabled(model.busy || model.running)
        }
    }
    private var controls: some View {
        HStack {
            if model.setupStep != .device && model.setupStep != .done && model.setupStep != .client {
                Button("上一步") { model.setupStep = SetupStep(rawValue: model.setupStep.rawValue - 1) ?? .device }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(model.busy)
            }
            Spacer()
            if model.setupStep != .done && model.setupStep != .client {
                Button(model.setupStep == .install ? model.error == nil ? "开始安装" : "重试安装" : "下一步") {
                    model.error = nil
                    if model.setupStep == .install { model.guidedInstall() }
                    else { model.setupStep = SetupStep(rawValue: model.setupStep.rawValue + 1) ?? .install }
                }.buttonStyle(OverButtonStyle(kind: .primary)).disabled(!canContinue || model.busy)
                    .accessibilityIdentifier("setupNext")
            }
        }
    }
    private var canContinue: Bool {
        switch model.setupStep {
        case .device: model.setupDevice?.canProceed == true
        case .source: model.freshInstall || model.importAssessment?.canProceed == true
        default: model.hasLoaded
        }
    }
    private func detail(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(name).foregroundStyle(LauncherTheme.muted); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
}
