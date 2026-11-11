import Foundation

struct ResolutionChoice: Codable, Hashable, Identifiable {
    var width: Int
    var height: Int
    var id: String { "\(width)x\(height)" }
    var title: String { "\(width) × \(height)" }

    static let choices: [ResolutionChoice] = [
        .init(width: 1920, height: 1080),
        .init(width: 1680, height: 945),
        .init(width: 1600, height: 900),
        .init(width: 1440, height: 810),
        .init(width: 1280, height: 720),
    ]
}

struct DisplaySettings: Codable, Equatable {
    var hiDPIEnabled = false
    /// "vendor-model-serial" of the panel HiDPI applies to; nil = first external display.
    var targetDisplay: String?
    var looksLike = ResolutionChoice(width: 1920, height: 1080)
    /// nil = leave the system default untouched.
    var fontSmoothing: Int?
    var softwareDimming = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplaySettings()
        hiDPIEnabled = c.value(.hiDPIEnabled, default: d.hiDPIEnabled)
        targetDisplay = c.value(.targetDisplay, default: d.targetDisplay)
        looksLike = c.value(.looksLike, default: d.looksLike)
        fontSmoothing = c.value(.fontSmoothing, default: d.fontSmoothing)
        softwareDimming = c.value(.softwareDimming, default: d.softwareDimming)
    }
}
