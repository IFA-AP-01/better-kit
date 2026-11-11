import AppKit
import CoreGraphics

/// A physical display as seen by CoreGraphics.
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let key: String
    let isBuiltin: Bool
    let pixelSize: CGSize
    let pointSize: CGSize
    let refreshRate: Double
    let mirrorOf: CGDirectDisplayID?

    var isHiDPI: Bool { pixelSize.width > pointSize.width }

    static let virtualVendorID: UInt32 = 0x4B42

    static func identity(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Online physical displays (BetterKit's own virtual display is left out).
    static func all() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).compactMap { id in
            guard CGDisplayVendorNumber(id) != virtualVendorID else { return nil }
            return DisplayInfo(id)
        }
    }

    init(_ id: CGDirectDisplayID) {
        self.id = id
        key = Self.identity(id)
        isBuiltin = CGDisplayIsBuiltin(id) != 0
        let mode = CGDisplayCopyDisplayMode(id)
        pixelSize = CGSize(width: mode?.pixelWidth ?? CGDisplayPixelsWide(id), height: mode?.pixelHeight ?? CGDisplayPixelsHigh(id))
        pointSize = CGSize(width: mode?.width ?? CGDisplayPixelsWide(id), height: mode?.height ?? CGDisplayPixelsHigh(id))
        let rate = mode?.refreshRate ?? 0
        refreshRate = rate > 0 ? rate : 60
        let master = CGDisplayMirrorsDisplay(id)
        mirrorOf = master == kCGNullDirectDisplay ? nil : master
        name = Self.name(for: id, key: key) ?? (isBuiltin ? "Built-in Display" : "Display \(id)")
    }

    private static let namesKey = "displayNames"

    /// A mirrored panel has no NSScreen of its own, so names seen earlier are remembered by display identity.
    private static func name(for id: CGDirectDisplayID, key: String) -> String? {
        var names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        guard let live = screen?.localizedName else { return names[key] }
        if names[key] != live {
            names[key] = live
            UserDefaults.standard.set(names, forKey: namesKey)
        }
        return live
    }
}
