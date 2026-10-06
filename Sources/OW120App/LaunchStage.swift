import SwiftUI
import AppKit

private typealias StageState<Value> = SwiftUI.State<Value>

/// Presentation only. Launch, import, stop and configuration remain owned by
/// LauncherView/LauncherModel; the stage never starts a game on its own.
struct LaunchStage<Actions: View>: View {
    let compact: Bool
    let portrait: NSImage?
    let heroTitle: String
    let heroEnglishName: String
    let status: String
    let statusColor: Color
    let machine: String
    let message: String
    @ViewBuilder var actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 18 : 36) {
            VStack(alignment: .leading, spacing: compact ? 18 : 24) {
                HStack(spacing: 12) {
                    Text("国服 · DX11").font(LauncherTheme.uiFont(12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(LauncherTheme.sidebar)
                        .background(Color(red: 1, green: 0.71, blue: 0.23), in: SlantedPanel())
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 5, height: 5)
                        Text(status).font(LauncherTheme.uiFont(12))
                    }.foregroundStyle(Color.white.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 4) {
                    GameDisplayText(text: "OVERWATCH", size: compact ? 46 : 66, spacing: 1.4)
                        .accessibilityHidden(true)
                    Text("守望先锋").font(LauncherTheme.chineseHeading(compact ? 32 : 40))
                        .fixedSize().padding(.trailing, 10).accessibilityAddTraits(.isHeader)
                    Text(machine).font(LauncherTheme.uiFont(12)).foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(2).padding(.top, 6)
                }
                actions
                Text(message).font(LauncherTheme.uiFont(12)).foregroundStyle(Color.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            LaunchHeroFacet(portrait: portrait, title: heroTitle, englishName: heroEnglishName, compact: compact)
                .id(heroEnglishName).transition(.opacity)
                .frame(width: compact ? 156 : 232, height: compact ? 218 : 282)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: heroEnglishName)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.white)
        .padding(compact ? 24 : 32)
        .background(LaunchStageBackdrop().accessibilityHidden(true))
        .clipShape(LaunchStageOutline())
        .overlay(LaunchStageOutline().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .accessibilityIdentifier("launchStage")
    }
}

private struct LaunchStageOutline: InsettableShape {
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut: CGFloat = 22
        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut)); p.closeSubpath()
        }
    }
    func inset(by amount: CGFloat) -> Self { var copy = self; copy.insetAmount += amount; return copy }
}

private struct LaunchStageBackdrop: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LauncherTheme.sidebar))
            var plane = Path()
            plane.move(to: CGPoint(x: size.width * 0.62, y: 0))
            plane.addLine(to: CGPoint(x: size.width, y: 0)); plane.addLine(to: CGPoint(x: size.width, y: size.height))
            plane.addLine(to: CGPoint(x: size.width * 0.43, y: size.height)); plane.closeSubpath()
            context.fill(plane, with: .color(Color(red: 0.13, green: 0.20, blue: 0.33)))
            for index in 0..<3 {
                var line = Path()
                let x = size.width * 0.70 + CGFloat(index) * 18
                line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x - size.height * 0.38, y: size.height))
                context.stroke(line, with: .color(Color.white.opacity(index == 0 ? 0.10 : 0.04)), lineWidth: 1)
            }
            // A single static orange registration line, not a looping effect.
            context.fill(Path(CGRect(x: 0, y: 24, width: 3, height: 72)), with: .color(LauncherTheme.accent))
            for index in 0..<4 {
                context.fill(Path(CGRect(x: size.width - 86 + CGFloat(index) * 12, y: size.height - 16, width: 6, height: 2)),
                             with: .color(Color.white.opacity(0.25)))
            }
        }
    }
}

private struct LaunchHeroFacet: View {
    let portrait: NSImage?
    let title: String
    let englishName: String
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                Color(red: 0.76, green: 0.83, blue: 0.90)
                SlantedPanel().fill(Color.white.opacity(0.25)).padding(.leading, 24).offset(x: 14, y: -20)
                if let portrait {
                    Image(nsImage: portrait).resizable().interpolation(.high).scaledToFit()
                        .padding(.horizontal, compact ? 0 : 8).offset(y: 5)
                } else {
                    OWEmblem().padding(22)
                }
                HStack {
                    Rectangle().fill(LauncherTheme.accent).frame(width: 24, height: 3)
                    Spacer()
                    Image(systemName: "chevron.forward.2").font(.system(size: 9, weight: .bold))
                }.foregroundStyle(LauncherTheme.sidebar).padding(12)
            }
            .frame(height: compact ? 156 : 224)
            .clipShape(SlantedPanel())
            .overlay(SlantedPanel().stroke(Color.white.opacity(0.86), lineWidth: 2))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                GameDisplayText(text: englishName.uppercased(), size: compact ? 18 : 24, spacing: 0.5)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                Text(title).font(LauncherTheme.uiFont(11)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
            }
        }
    }
}

struct LaunchPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LaunchPrimarySurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

struct LaunchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LaunchSecondarySurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct LaunchSecondarySurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StageState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label.font(LauncherTheme.uiFont(12))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(hovering && enabled ? LauncherTheme.sidebar : Color.white.opacity(enabled ? 0.85 : 0.4))
            .background(hovering && enabled ? LauncherTheme.surface : Color.white.opacity(0.06), in: SlantedPanel())
            .overlay(SlantedPanel().stroke(focused ? Color.white : Color.clear, lineWidth: 2))
            .contentShape(SlantedPanel()).opacity(pressed ? 0.75 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

private struct LaunchPrimarySurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StageState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label.font(LauncherTheme.chineseHeading(24))
            .padding(.horizontal, 22).padding(.vertical, 16)
            .foregroundStyle(enabled ? LauncherTheme.sidebar : Color.white.opacity(0.60))
            .background(enabled ? Color(red: 1, green: hovering ? 0.76 : 0.66, blue: 0.22) : Color.white.opacity(0.12), in: SlantedPanel())
            .overlay(SlantedPanel().stroke(hovering || focused ? Color.white : Color.white.opacity(0.15), lineWidth: 2))
            .contentShape(SlantedPanel()).offset(x: hovering && enabled && !reduceMotion ? 3 : 0)
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
    }
}

struct LaunchProfileStrip: View {
    let mode: String
    let output: String
    let render: String
    let target: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            item("配置模式", mode)
            item("输出", output)
            item("3D 渲染", render)
            item("帧率目标", target)
        }.padding(.horizontal, 20).padding(.vertical, 16)
            .background(LauncherTheme.surface.opacity(0.72))
            .overlay(alignment: .leading) { Rectangle().fill(LauncherTheme.accent).frame(width: 3) }
    }
    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(LauncherTheme.uiFont(11)).foregroundStyle(LauncherTheme.muted)
            Text(value).font(LauncherTheme.uiFont(14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct LaunchHeroCard: View {
    let portrait: NSImage?
    let title: String
    let englishName: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    LauncherTheme.sidebar
                    if let portrait { Image(nsImage: portrait).resizable().scaledToFit() }
                    else { OWEmblem().padding(14) }
                }.frame(height: 76)
                GameDisplayText(text: englishName.uppercased(), size: 16, spacing: 0.1)
                    .lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .foregroundStyle(selected ? Color.white : LauncherTheme.text)
                    .background(selected ? LauncherTheme.blue : LauncherTheme.surface)
            }.frame(width: 92).clipShape(SlantedPanel())
                .overlay(SlantedPanel().stroke(selected ? Color(red: 1, green: 0.70, blue: 0.23) : Color.white.opacity(0.80), lineWidth: selected ? 3 : 1))
        }.buttonStyle(LaunchHeroCardStyle())
            .accessibilityLabel(title).accessibilityValue(selected ? "已选择应用图标" : "")
            .help("应用图标：\(title)")
    }
}

private struct LaunchHeroCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LaunchHeroCardSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct LaunchHeroCardSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StageState private var hovering = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label.overlay(SlantedPanel().stroke(hovering || focused ? Color.white : Color.clear, lineWidth: 2))
            .offset(y: hovering && !reduceMotion ? -2 : 0).opacity(pressed ? 0.8 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
