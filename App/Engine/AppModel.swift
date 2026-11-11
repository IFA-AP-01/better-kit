import Combine
import Foundation

/// Owns every feature model and persists their settings together.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    let permissions = PermissionsModel()
    let loginItem = LoginItem()
    let scroll: ScrollModel
    let display: DisplayModel
    let vietnamese: VietnameseModel
    let fan: FanModel
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        scroll = ScrollModel(settings: settings.scroll, permissions: permissions)
        display = DisplayModel(settings: settings.display)
        vietnamese = VietnameseModel(settings: settings.vietnamese, permissions: permissions)
        fan = FanModel(settings: settings.fan)

        scroll.onChange = { [weak self] in self?.persist() }
        display.onChange = { [weak self] in self?.persist() }
        vietnamese.onChange = { [weak self] in self?.persist() }
        fan.onChange = { [weak self] in self?.persist() }
        permissions.onChange = { [weak self] in self?.applyInputFeatures() }

        // Feature models publish on their own; forward so menus and windows bound to AppModel refresh.
        for publisher in [scroll.objectWillChange, display.objectWillChange, vietnamese.objectWillChange,
                          fan.objectWillChange, permissions.objectWillChange, loginItem.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    var needsOnboarding: Bool { !settings.onboardingDone }

    var needsAttention: Bool {
        let wantsInput = scroll.settings.enabled || vietnamese.settings.enabled
        return (wantsInput && !permissions.accessibility) || fan.helper.state == .requiresApproval
    }

    func start() {
        if !settings.launchAtLoginInitialized {
            loginItem.set(true)
            settings.launchAtLoginInitialized = true
            persist()
        }
        applyInputFeatures()
        display.start()
        fan.start()
    }

    func stop() {
        scroll.stop()
        vietnamese.stop()
        display.shutdown()
        fan.shutdown()
    }

    func finishOnboarding() {
        settings.onboardingDone = true
        persist()
    }

    private func applyInputFeatures() {
        scroll.apply()
        vietnamese.apply()
    }

    private func persist() {
        settings.scroll = scroll.settings
        settings.display = display.settings
        settings.vietnamese = vietnamese.settings
        settings.fan = fan.settings
        settings.save()
    }
}
