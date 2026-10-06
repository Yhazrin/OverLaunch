import Foundation

public struct OutputResolution: Identifiable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var id: String { "\(width)x\(height)" }
    public var title: String { "\(width) × \(height)" }
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public static let presets = [
        OutputResolution(width: 1280, height: 720), OutputResolution(width: 1280, height: 800),
        OutputResolution(width: 1440, height: 900), OutputResolution(width: 1600, height: 900),
        OutputResolution(width: 1600, height: 1000), OutputResolution(width: 1920, height: 1080),
        OutputResolution(width: 1920, height: 1200), OutputResolution(width: 2560, height: 1440),
        OutputResolution(width: 2560, height: 1600),
        OutputResolution(width: 2048, height: 1152), OutputResolution(width: 2048, height: 1280),
        OutputResolution(width: 2560, height: 1080), OutputResolution(width: 2880, height: 1800),
        OutputResolution(width: 3440, height: 1440), OutputResolution(width: 3840, height: 1600),
        OutputResolution(width: 3840, height: 2160), OutputResolution(width: 3840, height: 2400)
    ]
    public func applying(to profile: GameProfile) -> GameProfile {
        profile.withFixedOutput(width: width, height: height)
    }
}
