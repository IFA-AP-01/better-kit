import Foundation

@MainActor
final class VietnameseModel: ObservableObject {
    @Published var settings: VietnameseSettings {
        didSet {
            guard settings != oldValue else { return }
            apply()
            onChange?()
        }
    }
    @Published private(set) var isActive = false
    var onChange: (() -> Void)?

    private let tap = VietKeyTap()
    private let permissions: PermissionsModel

    init(settings: VietnameseSettings, permissions: PermissionsModel) {
        self.settings = settings
        self.permissions = permissions
        tap.onToggle = { [weak self] on in self?.languageToggled(on) }
        FrontmostApp.shared.observe { [weak self] id in
            MainActor.assumeIsolated { self?.appSwitched(id) }
        }
    }

    var isVietnamese: Bool { settings.vietnameseOn }

    var menuBarLetter: String? {
        guard settings.enabled else { return nil }
        return settings.vietnameseOn ? "V" : "E"
    }

    func toggleLanguage() {
        languageToggled(!settings.vietnameseOn)
    }

    func apply() {
        tap.update(.init(method: settings.method, modern: settings.modernOrthography,
                         englishOverride: settings.englishOverride, quickTelex: settings.quickTelex,
                         hotkey: settings.hotkey, exclusions: Set(settings.exclusions.map(\.bundleID))))
        tap.setVietnamese(settings.vietnameseOn)
        if settings.enabled, permissions.accessibility {
            if !tap.isRunning, !tap.start() {
                Log.vietnamese.error("keyboard tap refused; Accessibility missing?")
            }
        } else if tap.isRunning {
            tap.stop()
        }
        isActive = tap.isRunning
    }

    func stop() {
        tap.stop()
        isActive = false
    }

    private func languageToggled(_ on: Bool) {
        var s = settings
        s.vietnameseOn = on
        if s.rememberPerApp, let app = FrontmostApp.shared.bundleID {
            s.appLanguage[app] = on
        }
        settings = s
    }

    private func appSwitched(_ id: String?) {
        tap.resetWord()
        guard settings.enabled, settings.rememberPerApp, let id, let on = settings.appLanguage[id],
              on != settings.vietnameseOn else { return }
        settings.vietnameseOn = on
    }
}
