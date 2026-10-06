import Foundation

public enum ConfigurationMode: String, Codable, CaseIterable, Sendable {
    case automatic, performance, balanced, clarity, manual
    public var title: String {
        switch self {
        case .automatic: "自动匹配"
        case .performance: "流畅优先"
        case .balanced: "均衡"
        case .clarity: "清晰优先"
        case .manual: "手动"
        }
    }
}

/// Workload-based starting settings, not a measured FPS prediction. Desktop
/// dimensions use Wine's logical pixel coordinate space, never Retina pixels.
public enum LaunchConfiguration {
    public static func match(_ mode: ConfigurationMode, machine: MachineInfo, current: GameProfile) -> GameProfile {
        guard mode != .manual else { return current }
        var result = GameProfile.recommended(memoryGB: machine.memoryGB, chip: machine.chip)
        result.configurationMode = mode
        let desktopWidth = machine.desktopWidth ?? current.width
        let desktopHeight = machine.desktopHeight ?? current.height
        let width = (640...8192).contains(desktopWidth) ? desktopWidth : 1600
        let height = (480...8192).contains(desktopHeight) ? desktopHeight : 1000
        result = result.fittingDesktop(width: width, height: height)
        let largerGPU = machine.chip.localizedCaseInsensitiveContains("Pro") || machine.chip.localizedCaseInsensitiveContains("Max") || machine.chip.localizedCaseInsensitiveContains("Ultra")
        var budget = largerGPU ? 1920.0 * 1200 : 1600.0 * 1000
        var preferredScale = result.effectiveRenderScale
        if machine.memoryGB <= 16 { budget = 1280 * 800 }
        if mode == .performance {
            budget = min(budget, 1440 * 900)
            preferredScale = min(preferredScale, machine.memoryGB <= 16 ? 67 : 75)
        } else if mode == .balanced {
            budget = largerGPU ? 2560 * 1600 : machine.memoryGB <= 16 ? 1280 * 800 : 1920 * 1200
            preferredScale = machine.memoryGB <= 16 ? 80 : 90
        } else if mode == .clarity {
            budget = largerGPU ? 2560 * 1600 : 1920 * 1200
            preferredScale = 100
        }
        if machine.lowPowerMode && mode != .clarity {
            budget = min(budget, 1280 * 800)
            preferredScale = min(preferredScale, 75)
        }
        let area = Double(width) * Double(height)
        let limit = Int((sqrt(budget / area) * 100).rounded(.down))
        // Extremely large desktops cannot fit the budget at 50% scale. Use a
        // Retina-aware window instead of silently stretching fullscreen input.
        if limit < 50 || (mode == .clarity && area > budget) {
            let aspect = Double(width) / Double(height)
            let candidates = OutputResolution.presets.filter { Double($0.width) * Double($0.height) <= budget }
            let best = candidates.min { left, right in
                let l = abs(Double(left.width) / Double(left.height) - aspect)
                let r = abs(Double(right.width) / Double(right.height) - aspect)
                if abs(l - r) > 0.01 { return l < r }
                return left.width * left.height > right.width * right.height
            } ?? OutputResolution(width: 1280, height: 800)
            result = best.applying(to: result)
            result.renderScalePercent = preferredScale
        } else {
            result.renderScalePercent = mode == .clarity ? 100 : max(50, min(preferredScale, (limit / 5) * 5))
        }
        result.targetFPS = [120, 144, 165, 240].filter { Double($0) <= machine.displayHz + 1 }.last ?? 120
        return result
    }
}
