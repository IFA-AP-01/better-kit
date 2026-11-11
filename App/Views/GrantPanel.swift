import AppKit
import SwiftUI

/// Floating helper shown next to System Settings: it explains the step and offers the
/// BetterKit icon as a drag source to drop straight into the permission list.
@MainActor
final class GrantPanelController {
    static let shared = GrantPanelController()

    private var panel: NSPanel?
    private var kind: GrantKind?
    private var followTimer: Timer?

    func show(_ kind: GrantKind) {
        self.kind = kind
        kind.openSettings()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: GrantPanelView(kind: kind) { [weak self] in self?.close() })
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        place(panel)
        panel.orderFrontRegardless()
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.place(panel)
            }
        }
    }

    func permissionGranted(_ granted: GrantKind) {
        guard kind == granted else { return }
        close()
    }

    func close() {
        followTimer?.invalidate()
        followTimer = nil
        panel?.orderOut(nil)
        kind = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    /// Docks the panel beside the System Settings window (left side if there is no room on the right).
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let frame = Self.settingsWindowFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            if let screen = NSScreen.main, !panel.isVisible {
                let v = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24, y: v.maxY - size.height - 24))
            }
            return
        }
        let visible = screen.visibleFrame
        var x = frame.maxX + 12
        if x + size.width > visible.maxX { x = frame.minX - size.width - 12 }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = frame.maxY - size.height
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        let origin = NSPoint(x: x, y: y)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    /// System Settings' main window in Cocoa coordinates (CGWindowList uses a top-left origin).
    private static func settingsWindowFrame() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let pid = app.processIdentifier
        let windows = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        guard let bounds = windows.compactMap({ $0[kCGWindowBounds as String] as? NSDictionary })
                .compactMap({ CGRect(dictionaryRepresentation: $0) })
                .max(by: { $0.width * $0.height < $1.width * $1.height }),
              let primary = NSScreen.screens.first else { return nil }
        return NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}

struct GrantPanelView: View {
    let kind: GrantKind
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(kind.title)
                .font(.system(size: 14, weight: .semibold))
            if kind.allowsDrag {
                VStack(spacing: 6) {
                    AppDragSource()
                        .frame(width: 72, height: 72)
                    Text("BetterKit")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Color.accentColor.opacity(0.6)))
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            Text(kind.instructions)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings Again") { kind.openSettings() }
                Spacer()
                Button("Close", action: onClose)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(width: 280)
    }
}

/// The app icon as an AppKit drag source carrying BetterKit's bundle URL.
struct AppDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ nsView: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    private let icon = NSApp.applicationIconImage ?? NSImage()

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
