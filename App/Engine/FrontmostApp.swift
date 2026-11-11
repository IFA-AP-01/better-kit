import AppKit

/// The frontmost app's bundle ID, readable from event-tap threads without touching AppKit.
final class FrontmostApp {
    static let shared = FrontmostApp()

    private let lock = NSLock()
    private var current: String?
    private var observers: [(String?) -> Void] = []

    private init() {
        current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(app?.bundleIdentifier)
        }
    }

    var bundleID: String? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Called on the main thread after every app switch.
    func observe(_ block: @escaping (String?) -> Void) {
        observers.append(block)
    }

    private func update(_ id: String?) {
        lock.lock(); current = id; lock.unlock()
        observers.forEach { $0(id) }
    }
}

/// An app picked for an exception list.
struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    @MainActor
    static func choose() -> [AppRef] {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose apps"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return AppRef(bundleID: id, name: name)
        }
    }
}
