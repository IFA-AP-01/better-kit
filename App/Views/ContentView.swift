import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case general, scroll, display, vietnamese, fans, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .scroll: "Smooth Scroll"
        case .display: "Display"
        case .vietnamese: "Vietnamese"
        case .fans: "Fans"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .scroll: "computermouse"
        case .display: "display"
        case .vietnamese: "keyboard"
        case .fans: "fan"
        case .about: "info.circle"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateCoordinator
    @ObservedObject var whatsNew: WhatsNewTracker
    @AppStorage("mainSection") private var section: MainSection = .general

    private var sections: [MainSection] {
        MainSection.allCases.filter { $0 != .fans || model.fan.hasFans }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<MainSection?>(get: { section }, set: { if let value = $0 { section = value } })) {
                ForEach(sections) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(badge(for: item))
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch section {
            case .general: GeneralPane(model: model, permissions: model.permissions, loginItem: model.loginItem, helper: model.fan.helper)
            case .scroll: ScrollPane(scroll: model.scroll, permissions: model.permissions)
            case .display: DisplayPane(display: model.display)
            case .vietnamese: VietnamesePane(vietnamese: model.vietnamese, permissions: model.permissions)
            case .fans: FanPane(fan: model.fan, helper: model.fan.helper)
            case .about: AboutPane(updates: updates, whatsNew: whatsNew)
            }
        }
        .navigationTitle("BetterKit")
        .sheet(isPresented: $whatsNew.isPresented) {
            WhatsNewView(version: whatsNew.version, notes: whatsNew.notes)
        }
    }

    private func badge(for item: MainSection) -> Text? {
        switch item {
        case .general: model.needsAttention ? Text("!") : nil
        default: nil
        }
    }
}
