import Foundation

@MainActor
final class ScrollModel: ObservableObject {
    @Published var settings: ScrollSettings {
        didSet {
            guard settings != oldValue else { return }
            apply()
            onChange?()
        }
    }
    @Published private(set) var isActive = false
    var onChange: (() -> Void)?

    private let scroller = SmoothScroller()
    private let permissions: PermissionsModel

    init(settings: ScrollSettings, permissions: PermissionsModel) {
        self.settings = settings
        self.permissions = permissions
    }

    func apply() {
        scroller.update(.init(smooth: settings.smooth, reverse: settings.reverse, step: settings.step,
                              speed: settings.speed, duration: settings.duration,
                              exceptions: Set(settings.exceptions.map(\.bundleID))))
        if settings.enabled, permissions.accessibility {
            if !scroller.isRunning, !scroller.start() {
                Log.scroll.error("scroll tap refused; Accessibility missing?")
            }
        } else if scroller.isRunning {
            scroller.stop()
        }
        isActive = scroller.isRunning
    }

    func stop() {
        scroller.stop()
        isActive = false
    }
}
