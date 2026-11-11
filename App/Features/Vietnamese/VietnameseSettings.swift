import CoreGraphics
import Foundation

enum InputMethod: Int, Codable, CaseIterable, Identifiable {
    case telex = 0
    case vni = 1
    case simpleTelex = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .telex: "Telex"
        case .vni: "VNI"
        case .simpleTelex: "Simple Telex"
        }
    }
}

/// A modifier-only shortcut (pressed together, then released) that flips VN/EN.
struct ModifierHotkey: Codable, Equatable, Hashable {
    var control = true
    var option = false
    var shift = true
    var command = false

    var flags: CGEventFlags {
        var f = CGEventFlags()
        if control { f.insert(.maskControl) }
        if option { f.insert(.maskAlternate) }
        if shift { f.insert(.maskShift) }
        if command { f.insert(.maskCommand) }
        return f
    }

    var isValid: Bool { [control, option, shift, command].filter { $0 }.count >= 2 }

    var symbols: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
    }

    static let presets: [ModifierHotkey] = [
        ModifierHotkey(control: true, option: false, shift: true, command: false),
        ModifierHotkey(control: false, option: false, shift: true, command: true),
        ModifierHotkey(control: true, option: true, shift: false, command: false),
        ModifierHotkey(control: false, option: true, shift: false, command: true),
    ]
}

struct VietnameseSettings: Codable, Equatable {
    var enabled = false
    var vietnameseOn = true
    var method: InputMethod = .telex
    var modernOrthography = true
    var englishOverride = true
    var quickTelex = false
    var hotkey = ModifierHotkey()
    var rememberPerApp = true
    var appLanguage: [String: Bool] = [:]
    var exclusions: [AppRef] = VietnameseSettings.defaultExclusions

    static let defaultExclusions = [
        AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
        AppRef(bundleID: "com.googlecode.iterm2", name: "iTerm"),
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VietnameseSettings()
        enabled = c.value(.enabled, default: d.enabled)
        vietnameseOn = c.value(.vietnameseOn, default: d.vietnameseOn)
        method = c.value(.method, default: d.method)
        modernOrthography = c.value(.modernOrthography, default: d.modernOrthography)
        englishOverride = c.value(.englishOverride, default: d.englishOverride)
        quickTelex = c.value(.quickTelex, default: d.quickTelex)
        hotkey = c.value(.hotkey, default: d.hotkey)
        rememberPerApp = c.value(.rememberPerApp, default: d.rememberPerApp)
        appLanguage = c.value(.appLanguage, default: d.appLanguage)
        exclusions = c.value(.exclusions, default: d.exclusions)
    }
}
