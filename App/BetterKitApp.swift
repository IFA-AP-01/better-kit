import SwiftUI

@main
struct BetterKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { delegate.updates.checkForUpdates() }
                Button("What's New in BetterKit…") { delegate.showWhatsNew() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Open BetterKit…") { delegate.showMainWindow() }
                    .keyboardShortcut(",")
                Button("Setup Guide…") { delegate.showOnboarding() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updates = UpdateCoordinator()
    let whatsNew = WhatsNewTracker()
    private var statusMenu: StatusMenuController?
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        statusMenu = StatusMenuController(
            model: model,
            onOpenMain: { [weak self] section in self?.showMainWindow(section: section) },
            onOpenOnboarding: { [weak self] in self?.showOnboarding() },
            updates: updates
        )
        updates.start()
        whatsNew.checkOnLaunch()
        if model.needsOnboarding {
            showOnboarding()
        } else if whatsNew.isPresented {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showWhatsNew() {
        showMainWindow()
        whatsNew.show()
    }

    func showMainWindow(section: MainSection? = nil) {
        if let section {
            UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
        }
        if mainWindow == nil {
            let root = ContentView(model: model, updates: updates, whatsNew: whatsNew)
                .frame(minWidth: 760, minHeight: 540)
            let window = makeWindow(title: "BetterKit", autosave: "MainWindow", content: root,
                                    style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    bridgesToolbar: true)
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 760, height: 540)
            if window.frame.width < 860 {
                window.setContentSize(NSSize(width: 880, height: 640))
                window.center()
            }
            mainWindow = window
        }
        present(mainWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let root = OnboardingView(model: model, permissions: model.permissions, loginItem: model.loginItem) { [weak self] in
                self?.model.finishOnboarding()
                self?.onboardingWindow?.close()
            }
            onboardingWindow = makeWindow(title: "Welcome to BetterKit", autosave: "OnboardingWindow", content: root,
                                          style: [.titled, .closable])
        }
        present(onboardingWindow)
    }

    private func makeWindow<Content: View>(title: String, autosave: String, content: Content, style: NSWindow.StyleMask,
                                         bridgesToolbar: Bool = false) -> NSWindow {
        let host = NSHostingController(rootView: content)
        if bridgesToolbar {
            host.sceneBridgingOptions = [.toolbars]
            host.sizingOptions = []
        }
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosave)
        if !window.setFrameUsingName(autosave) {
            window.center()
        }
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
