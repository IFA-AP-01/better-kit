import Foundation

enum FanPreset: String, Codable, CaseIterable, Identifiable {
    case automatic
    case constant
    case curve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .constant: "Constant speed"
        case .curve: "Sensor-based"
        }
    }
}

struct FanSettings: Codable, Equatable {
    var preset: FanPreset = .automatic
    /// 0…1 between each fan's minimum and maximum speed.
    var constantLevel: Double = 0.3
    /// SMC key the curve follows; nil = hottest CPU core.
    var curveSensor: String?
    var curveLow: Double = 50
    var curveHigh: Double = 85

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FanSettings()
        preset = c.value(.preset, default: d.preset)
        constantLevel = c.value(.constantLevel, default: d.constantLevel)
        curveSensor = c.value(.curveSensor, default: d.curveSensor)
        curveLow = c.value(.curveLow, default: d.curveLow)
        curveHigh = c.value(.curveHigh, default: d.curveHigh)
    }
}
