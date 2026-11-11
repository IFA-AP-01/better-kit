import SwiftUI

struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var helper: FanHelperClient

    var body: some View {
        Form {
            Section {
                Toggle("Open BetterKit at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if loginItem.requiresApproval {
                    Text("Approve BetterKit in System Settings › General › Login Items.")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let error = loginItem.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            }

            Section {
                SetupRow(symbol: "hand.raised", title: "Accessibility",
                         detail: "Used by Smooth Scroll and Vietnamese typing to read and send input events.",
                         state: permissions.accessibility ? .done : .required,
                         actionTitle: "GRANT", action: { permissions.requestAccessibility() })
                if model.fan.hasFans {
                    SetupRow(symbol: "fan", title: "Fan helper",
                             detail: helperDetail,
                             state: helper.state == .enabled ? .done : .optional,
                             actionTitle: helper.state == .requiresApproval ? "APPROVE" : "INSTALL",
                             action: { helper.register() })
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Grant opens the right page in System Settings and shows a small panel: drag BetterKit into the list, then switch it on.")
            }

            Section {
                FeatureSummaryRow(symbol: "computermouse", tint: .blue, title: "Smooth Scroll",
                                  isOn: Binding(get: { model.scroll.settings.enabled }, set: { model.scroll.settings.enabled = $0 }))
                FeatureSummaryRow(symbol: "display", tint: .purple, title: "HiDPI",
                                  isOn: Binding(get: { model.display.settings.hiDPIEnabled }, set: { model.display.settings.hiDPIEnabled = $0 }))
                FeatureSummaryRow(symbol: "keyboard", tint: .red, title: "Vietnamese typing",
                                  isOn: Binding(get: { model.vietnamese.settings.enabled }, set: { model.vietnamese.settings.enabled = $0 }))
            } header: {
                Text("Tools")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            permissions.refresh()
            loginItem.refresh()
            helper.refresh()
        }
    }

    private var helperDetail: String {
        switch helper.state {
        case .enabled: "Installed. Fans return to automatic whenever BetterKit quits."
        case .requiresApproval: "Waiting for approval under Login Items › Allow in the Background."
        case .notRegistered: "Needed only to change fan speeds. Reading temperatures works without it."
        case .unavailable(let message): message
        }
    }
}

struct FeatureSummaryRow: View {
    let symbol: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
    }
}
