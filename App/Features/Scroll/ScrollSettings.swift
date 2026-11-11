import Foundation

struct ScrollSettings: Codable, Equatable {
    var enabled = false
    var smooth = true
    var reverse = false
    /// Pixels scrolled per wheel notch.
    var step: Double = 60
    /// Multiplier applied to every notch (higher = faster).
    var speed: Double = 1.6
    /// Seconds a scroll takes to settle.
    var duration: Double = 0.32
    var exceptions: [AppRef] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollSettings()
        enabled = c.value(.enabled, default: d.enabled)
        smooth = c.value(.smooth, default: d.smooth)
        reverse = c.value(.reverse, default: d.reverse)
        step = c.value(.step, default: d.step)
        speed = c.value(.speed, default: d.speed)
        duration = c.value(.duration, default: d.duration)
        exceptions = c.value(.exceptions, default: d.exceptions)
    }
}
