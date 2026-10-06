import SwiftUI

private typealias InfoState<Value> = SwiftUI.State<Value>

struct SoftwareInfo {
    var name: String
    var version: String
    var repository: URL?
    static var current: SoftwareInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let release = (info["OverLaunchReleaseVersion"] ?? info["CFBundleShortVersionString"]) as? String
        let build = info["CFBundleVersion"] as? String
        let address = (info["OverLaunchRepositoryURL"] as? String).flatMap(URL.init(string:))
        return SoftwareInfo(
            name: info["CFBundleDisplayName"] as? String ?? "OverLaunch",
            version: release.map { $0 + (build.map { " (\($0))" } ?? "") } ?? "开发版本",
            repository: address?.scheme == "https" && address?.host != nil ? address : nil
        )
    }
    static var licenseText: String {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("THIRD_PARTY.md")
        let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("THIRD_PARTY.md")
        for file in [bundled, source].compactMap({ $0 }) {
            if let text = try? String(contentsOf: file, encoding: .utf8) { return text }
        }
        return "许可说明不可用。请重新安装完整应用。"
    }
}

struct SoftwareInfoView: View {
    var info: SoftwareInfo = .current
    @InfoState private var showLicenses = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("软件信息").font(LauncherTheme.chineseHeading(24)).accessibilityAddTraits(.isHeader)
            row("名称", info.name)
            row("版本", info.version)
            row("支持平台", "Apple Silicon · macOS 14+")
            row("运行组件", "Wine · DXMT")
            HStack {
                Text("项目仓库").foregroundStyle(LauncherTheme.muted)
                Spacer(minLength: 16)
                if let repository = info.repository { Link("查看项目", destination: repository) }
                else { Text("未公布") }
            }.font(LauncherTheme.uiFont(13))
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("独立社区项目，与暴雪、网易无隶属关系。")
                    .font(LauncherTheme.uiFont(12)).foregroundStyle(LauncherTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("第三方许可") { showLicenses = true }
                    .buttonStyle(OverButtonStyle(kind: .quiet))
            }
        }
        .accessibilityIdentifier("softwareInfo")
        .sheet(isPresented: $showLicenses) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("第三方许可").font(LauncherTheme.chineseHeading(28))
                    Spacer()
                    Button("关闭") { showLicenses = false }.buttonStyle(OverButtonStyle(kind: .quiet))
                        .keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(SoftwareInfo.licenseText).font(LauncherTheme.uiFont(13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                }.scrollIndicators(.never)
            }.padding(24).frame(width: 560, height: 430)
                .foregroundStyle(LauncherTheme.text).background(LauncherTheme.background)
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(LauncherTheme.muted)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(LauncherTheme.uiFont(13)).accessibilityElement(children: .combine)
    }
}
