import SwiftUI
import Observation

private typealias ControlState<Value> = SwiftUI.State<Value>
private let gameSelectCanvas = "gameSelectCanvas"
private let gameSelectRow: CGFloat = 44

private struct GameSelectHostKey: EnvironmentKey {
    static let defaultValue: GameSelectHost? = nil
}
extension EnvironmentValues {
    var gameSelectHost: GameSelectHost? {
        get { self[GameSelectHostKey.self] }
        set { self[GameSelectHostKey.self] = newValue }
    }
}

enum OverButtonKind { case primary, secondary, quiet, field }

struct OverNavigationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OverNavigationSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}
private struct OverNavigationSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @ControlState private var hovering = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label.overlay(SlantedPanel().stroke(focused ? LauncherTheme.cyan : hovering ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
            .brightness(hovering ? 0.06 : 0).opacity(pressed ? 0.8 : 1)
            .onHover { hovering = $0 }.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

struct OverButtonStyle: ButtonStyle {
    var kind: OverButtonKind = .secondary
    func makeBody(configuration: Configuration) -> some View {
        OverButtonSurface(label: configuration.label, pressed: configuration.isPressed, kind: kind)
    }
}

private struct OverButtonSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    let kind: OverButtonKind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ControlState private var hovering = false
    private var highlighted: Bool { enabled && (hovering || focused) }
    private var background: Color {
        if !enabled { return LauncherTheme.surface.opacity(0.5) }
        switch kind {
        case .primary: return highlighted ? Color(red: 1, green: 0.45, blue: 0.11) : LauncherTheme.accent
        case .quiet: return highlighted ? LauncherTheme.blue.opacity(0.10) : .clear
        case .secondary, .field: return highlighted ? .white : LauncherTheme.surface
        }
    }
    var body: some View {
        label.font(kind == .primary ? LauncherTheme.chineseHeading(20) : LauncherTheme.uiFont(14, weight: .semibold))
            .padding(.horizontal, kind == .field ? 12 : 20)
            .padding(.vertical, kind == .quiet ? 8 : 12)
            .foregroundStyle(!enabled ? LauncherTheme.muted.opacity(0.55) : kind == .primary ? .white : LauncherTheme.text)
            .background(background, in: SlantedPanel())
            .overlay(SlantedPanel().stroke(focused ? LauncherTheme.blue : highlighted ? Color.white : .clear, lineWidth: 2))
            .contentShape(SlantedPanel())
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
            .opacity(pressed ? 0.88 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
    }
}

struct GameChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
    init(_ value: Value, _ title: String) { self.value = value; self.title = title }
}

/// Window-level host so the list is drawn over scrolling pages, not as a
/// centered macOS popover. The menu is anchored to the value field.
@MainActor
@Observable
final class GameSelectHost {
    var session: Session?
    var canvasSize: CGSize = .zero
    var topInset: CGFloat = 8
    var dismissArmed = false
    struct Session {
        var id: UUID
        var frame: CGRect
        var menu: AnyView
    }
    func present(_ session: Session) {
        self.session = session
        dismissArmed = false
        DispatchQueue.main.async { self.dismissArmed = true }
    }
    func dismiss(_ id: UUID? = nil) {
        if let id, session?.id != id { return }
        session = nil
        dismissArmed = false
    }
}

/// Renders the open list in the same canvas as the setting row.
struct GameSelectPortalLayer: View {
    var host: GameSelectHost
    var body: some View {
        ZStack(alignment: .topLeading) {
            if host.session != nil {
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    guard host.dismissArmed else { return }
                    host.dismiss()
                }
            }
            if let session = host.session {
                session.menu
                    .id(session.id)
                    .frame(width: session.frame.width, height: session.frame.height, alignment: .top)
                    .offset(x: session.frame.minX, y: session.frame.minY)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(host.session != nil)
    }
}

/// Anchored dropdown matching the Overwatch options page: the list opens on the
/// value field, not as a system popover in the middle of the window.
struct GameSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [GameChoice<Value>]
    var compact = false
    @ControlState private var identity = UUID()
    @ControlState private var valueFrame = CGRect.zero
    @FocusState private var triggerFocused: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.gameSelectHost) private var host
    private var valueWidth: CGFloat { compact ? 208 : 284 }
    private var expanded: Bool { host?.session?.id == identity }
    private var listHeight: CGFloat { min(360, CGFloat(max(choices.count, 1)) * gameSelectRow) }
    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 12) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    Text(choices.first { $0.value == selection }?.title ?? "自定义")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(width: valueWidth, height: gameSelectRow)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { remember(geometry.frame(in: .named(gameSelectCanvas))) }
                            .onChange(of: geometry.frame(in: .named(gameSelectCanvas))) { _, frame in remember(frame) }
                    }
                }
            }
        }
        .buttonStyle(GameSettingRowStyle())
        .focusable().focused($triggerFocused)
        .accessibilityLabel(title)
        .accessibilityValue(choices.first { $0.value == selection }?.title ?? "自定义")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("显示选项列表")
        .onChange(of: compact) { _, _ in if expanded { publish() } }
        .onChange(of: enabled) { _, value in if !value { host?.dismiss(identity) } }
        .onDisappear { host?.dismiss(identity) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: expanded)
    }
    private func remember(_ frame: CGRect) {
        guard frame != valueFrame else { return }
        valueFrame = frame
        if expanded { DispatchQueue.main.async { publish() } }
    }
    private func toggle() {
        if expanded {
            host?.dismiss(identity)
            return
        }
        if valueFrame.width > 1 {
            publish()
        } else {
            DispatchQueue.main.async { publish() }
        }
    }
    private func publish() {
        guard let host, valueFrame.width > 1, valueFrame.height > 1 else { return }
        let placement = DropdownGeometry(anchor: valueFrame, canvas: host.canvasSize, topInset: host.topInset, idealHeight: listHeight)
        host.present(GameSelectHost.Session(
            id: identity,
            frame: placement.frame,
            menu: AnyView(GameSelectMenu(
                title: title,
                selection: $selection,
                choices: choices,
                width: placement.frame.width,
                listHeight: placement.frame.height,
                onDismiss: { host.dismiss(identity); triggerFocused = true }
            ))
        ))
    }
}

struct GameSelectMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [GameChoice<Value>]
    let width: CGFloat
    let listHeight: CGFloat
    let onDismiss: () -> Void
    @FocusState private var focusedValue: Value?
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(choices) { choice in
                        Button {
                            selection = choice.value
                            onDismiss()
                        } label: {
                            HStack {
                                Text(choice.title).lineLimit(2)
                                Spacer(minLength: 8)
                                if selection == choice.value {
                                    Image(systemName: "checkmark").font(LauncherTheme.uiFont(12, weight: .bold))
                                }
                            }
                            .font(LauncherTheme.uiFont(14, weight: selection == choice.value ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: gameSelectRow, alignment: .leading)
                            .foregroundStyle(selection == choice.value ? Color.white : LauncherTheme.text)
                            .background(selection == choice.value ? LauncherTheme.blue : LauncherTheme.surface)
                        }
                        .buttonStyle(GameListButtonStyle())
                        .id(choice.value).focusable()
                        .focused($focusedValue, equals: choice.value)
                        .accessibilityValue(selection == choice.value ? "已选中" : "")
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: listHeight)
            .background(LauncherTheme.surface)
            .onChange(of: focusedValue) { _, value in
                if let value { reader.scrollTo(value, anchor: .center) }
            }
            .onAppear {
                focusedValue = choices.contains(where: { $0.value == selection }) ? selection : choices.first?.value
                if let value = focusedValue { reader.scrollTo(value, anchor: .center) }
            }
        }
        .frame(width: width, height: listHeight)
        .overlay(Rectangle().strokeBorder(LauncherTheme.sidebar.opacity(0.35), lineWidth: 1))
        .onExitCommand { onDismiss() }
        .onKeyPress(.return) {
            guard let value = focusedValue else { return .ignored }
            selection = value; onDismiss(); return .handled
        }
        .onMoveCommand { direction in
            guard let index = choices.firstIndex(where: { $0.value == focusedValue }) else { return }
            if direction == .down { focusedValue = choices[min(choices.count - 1, index + 1)].value }
            if direction == .up { focusedValue = choices[max(0, index - 1)].value }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct GameListButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GameListSurface(label: configuration.label, pressed: configuration.isPressed) }
}
private struct GameListSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @ControlState private var hovering = false
    @Environment(\.isFocused) private var focused
    var body: some View {
        label.overlay(Rectangle().stroke(hovering || focused ? LauncherTheme.blue : .clear, lineWidth: 2))
            .brightness(hovering ? 0.035 : 0).opacity(pressed ? 0.8 : 1).onHover { hovering = $0 }
    }
}

/// The entire setting row highlights, like the supplied Overwatch options page.
struct GameSettingRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GameSettingRowSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}
private struct GameSettingRowSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @ControlState private var hovering = false
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Bool { enabled && (hovering || focused) }
    var body: some View {
        label.font(LauncherTheme.uiFont(14))
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(active ? LauncherTheme.text : Color.white.opacity(0.95))
            .background(active ? Color.white : LauncherTheme.settingRow)
            .overlay(Rectangle().strokeBorder(focused ? LauncherTheme.blue : .clear, lineWidth: 2))
            .contentShape(Rectangle()).opacity(!enabled ? 0.5 : pressed ? 0.8 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: active)
    }
}

struct GameToggle: View {
    let title: String
    @Binding var value: Bool
    var compact = false
    var body: some View {
        Button { value.toggle() } label: {
            HStack(spacing: 12) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text(value ? "开启" : "关闭")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }.frame(width: compact ? 208 : 284)
            }
        }.buttonStyle(GameSettingRowStyle())
            .accessibilityLabel(title).accessibilityValue(value ? "开启" : "关闭")
            .onMoveCommand { direction in
                if direction == .left || direction == .right { value.toggle() }
            }
    }
}

struct GameRange: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 50...100
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(LauncherTheme.uiFont( 14)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(value)%").font(LauncherTheme.uiFont( 14)).monospacedDigit().foregroundStyle(.white).frame(width: 48, alignment: .trailing)
            GeometryReader { geometry in
                let travel = max(1, geometry.size.width - 16)
                let ratio = min(1, max(0, Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 5)
                    Capsule().fill(LauncherTheme.cyan).frame(width: 8 + travel * ratio, height: 5)
                    Circle().fill(.white).frame(width: 16, height: 16).offset(x: travel * ratio)
                }.frame(maxHeight: .infinity).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        guard enabled else { return }
                        let normalized = min(1, max(0, (event.location.x - 8) / travel))
                        value = range.lowerBound + Int((normalized * Double(range.upperBound - range.lowerBound)).rounded())
                    })
            }.frame(width: 200, height: 40)
        }.padding(.horizontal, 15).frame(height: 44).background(LauncherTheme.settingRow)
            .overlay(Rectangle().stroke(focused ? LauncherTheme.cyan : .clear, lineWidth: 2))
            .focusable().accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue("\(value)%")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
            }
            .onMoveCommand { direction in
                guard enabled else { return }
                if direction == .left || direction == .right { value = min(range.upperBound, max(range.lowerBound, value + (direction == .right ? 1 : -1))) }
            }
            .opacity(enabled ? 1 : 0.55)
    }
}

struct GameNumberField: View {
    let title: String
    @Binding var value: Int
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(LauncherTheme.uiFont( 13)).foregroundStyle(LauncherTheme.muted)
            TextField(title, value: $value, format: .number.grouping(.never))
                .textFieldStyle(.plain).multilineTextAlignment(.center).font(LauncherTheme.uiFont( 14)).focused($focused)
                .padding(12).background(LauncherTheme.surface)
                .overlay(Rectangle().stroke(focused ? LauncherTheme.blue : LauncherTheme.rule, lineWidth: focused ? 2 : 1))
                .accessibilityLabel(title)
        }
    }
}

struct GameSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(LauncherTheme.muted)
            TextField("搜索英雄", text: $text).textFieldStyle(.plain).focused($focused)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
        }.padding(13).background(LauncherTheme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(focused ? LauncherTheme.blue : LauncherTheme.rule).frame(height: focused ? 2 : 1) }
            .accessibilityLabel("搜索英雄")
    }
}

struct HeroTileStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        HeroTileSurface(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}
private struct HeroTileSurface<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @ControlState private var hovering = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        label.overlay(Rectangle().stroke(focused || hovering ? Color.white : .clear, lineWidth: 2))
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.98 : hovering ? 1.05 : 1)
            .onHover { hovering = $0 }.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
