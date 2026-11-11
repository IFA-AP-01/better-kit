import SwiftUI

/// First-run setup: what BetterKit does, the one permission it needs, and which tools to turn on.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var loginItem: LoginItem
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to BetterKit").font(.system(size: 20, weight: .semibold))
                    Text("Pick the tools you want. Everything lives in the menu bar and can be changed later.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                ToolCard(symbol: "computermouse.fill", tint: .blue, title: "Smooth Scroll",
                         detail: "Eased scrolling for mouse wheels.",
                         isOn: Binding(get: { model.scroll.settings.enabled }, set: { model.scroll.settings.enabled = $0 }))
                ToolCard(symbol: "display", tint: .purple, title: "HiDPI",
                         detail: "Sharper text on 1080p and other low-density displays.",
                         isOn: Binding(get: { model.display.settings.hiDPIEnabled }, set: { model.display.settings.hiDPIEnabled = $0 }))
                ToolCard(symbol: "character.textbox", tint: .red, title: "Vietnamese typing",
                         detail: "Telex / VNI. Switch with \(model.vietnamese.settings.hotkey.symbols).",
                         isOn: Binding(get: { model.vietnamese.settings.enabled }, set: { model.vietnamese.settings.enabled = $0 }))
            }

            SetupRow(symbol: "hand.raised", title: "Accessibility",
                     detail: "Needed by Smooth Scroll and Vietnamese typing. Click Grant, then drag BetterKit into the list.",
                     state: permissions.accessibility ? .done : (needsAccessibility ? .required : .optional),
                     actionTitle: "GRANT", action: { permissions.requestAccessibility() })

            HStack {
                Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .onAppear {
            permissions.refresh()
            loginItem.refresh()
        }
    }

    private var needsAccessibility: Bool {
        model.scroll.settings.enabled || model.vietnamese.settings.enabled
    }
}

private struct ToolCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
