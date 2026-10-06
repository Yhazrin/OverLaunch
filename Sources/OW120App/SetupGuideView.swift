import SwiftUI
import OW120Core

enum SetupStep: Int, CaseIterable {
    case device, source, profile, install, done
    var title: String { ["检查设备", "选择游戏", "启动设置", "安装组件", "安装完成"][rawValue] }
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
            Text("此版导入已有国服战网和守望先锋容器。运行组件由应用下载，后续运行不需要商业 CrossOver 授权。")
                .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
        }.font(LauncherTheme.uiFont(13))
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            Text("尚无游戏容器？当前版本暂不提供从零安装战网的流程。").font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted)
        }
    }
    private var install: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("首次下载运行组件约 367 MB；游戏从本机容器导入。")
            Text("下载与校验 → 导入游戏 → 安装图形组件 → 检查 Windows 启动能力")
                .foregroundStyle(LauncherTheme.muted)
            if model.busy {
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text(model.status).fixedSize(horizontal: false, vertical: true) }
            } else if model.error == nil { Text("点击“开始安装”准备独立环境。") }
            else { Text("安装未完成，可以重试。现有源容器仍然保留。").foregroundStyle(LauncherTheme.accent) }
        }.font(LauncherTheme.uiFont(13))
    }
    private var complete: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("独立环境已就绪", systemImage: "checkmark.circle.fill").font(LauncherTheme.uiFont(18, weight: .semibold))
            LaunchProfileStrip(mode: model.savedProfile.selectedConfigurationMode.title,
                               output: model.savedProfile.borderless && model.savedProfile.disableRetina ? "跟随桌面" : "\(model.savedProfile.width) × \(model.savedProfile.height)",
                               render: "\(model.savedProfile.effectiveRenderScale)%", target: "\(model.savedProfile.targetFPS) FPS")
            Text("打开国服战网，完成登录、验证码和游戏更新，再进入守望先锋。启动时会检查系统图形环境。")
                .font(LauncherTheme.uiFont(13)).foregroundStyle(LauncherTheme.muted)
            Button("打开国服战网") { model.dismissSetup(); model.launch() }
                .buttonStyle(OverButtonStyle(kind: .primary)).disabled(model.busy || model.running)
        }
    }
    private var controls: some View {
        HStack {
            if model.setupStep != .device && model.setupStep != .done {
                Button("上一步") { model.setupStep = SetupStep(rawValue: model.setupStep.rawValue - 1) ?? .device }
                    .buttonStyle(OverButtonStyle(kind: .quiet)).disabled(model.busy)
            }
            Spacer()
            if model.setupStep != .done {
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
        case .source: model.importAssessment?.canProceed == true
        default: model.hasLoaded
        }
    }
    private func detail(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(name).foregroundStyle(LauncherTheme.muted); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
}
