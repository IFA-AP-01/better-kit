import AppKit
import ApplicationServices

/// Live permission state. Polls while something is missing so the UI flips to Done
/// the moment the user enables BetterKit in System Settings.
@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    var onChange: (() -> Void)?
    private var timer: Timer?

    init() {
        if accessibility { UserDefaults.standard.set(true, forKey: GrantKind.accessibilityGrantedKey) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility {
            accessibility = trusted
            if trusted {
                UserDefaults.standard.set(true, forKey: GrantKind.accessibilityGrantedKey)
                GrantPanelController.shared.permissionGranted(.accessibility)
            }
            onChange?()
        }
    }

    func requestAccessibility() {
        GrantPanelController.shared.show(.accessibility)
    }
}

enum GrantKind: Equatable {
    case accessibility
    case backgroundItems

    var title: String {
        switch self {
        case .accessibility: "Allow Accessibility"
        case .backgroundItems: "Allow in the Background"
        }
    }

    static let accessibilityGrantedKey = "accessibilityGrantedOnce"

    var instructions: String {
        switch self {
        case .accessibility where UserDefaults.standard.bool(forKey: Self.accessibilityGrantedKey):
            "BetterKit was replaced by a new build, so macOS no longer matches the old entry. Select BetterKit in the list, remove it with –, then drag it in again and turn it on."
        case .accessibility:
            "Drag BetterKit into the Accessibility list, then turn its switch on."
        case .backgroundItems:
            "Find BetterKit under “Allow in the Background” and turn its switch on."
        }
    }

    var allowsDrag: Bool { self == .accessibility }

    func openSettings() {
        switch self {
        case .accessibility:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case .backgroundItems:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }
}
