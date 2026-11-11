import SwiftUI

struct SetupRow: View {
    enum State {
        case done
        case required
        case optional
        case checking
    }

    let symbol: String
    let title: String
    let detail: String
    let state: State
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .animation(.interpolatingSpring(mass: 1, stiffness: 200, damping: 14, initialVelocity: 6), value: state)
    }

    private var tint: Color {
        state == .required ? .orange : .accentColor
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
        case .checking:
            ProgressView().controlSize(.small).padding(.horizontal, 12)
        case .required, .optional:
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(state == .required ? .orange : .accentColor)
        }
    }
}

struct SetupBanner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 12)
            actions()
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }
}

/// Per-app exception list with an add button that opens an app chooser.
struct AppListEditor: View {
    @Binding var apps: [AppRef]
    let emptyText: String

    var body: some View {
        if apps.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        }
        ForEach(apps) { app in
            HStack(spacing: 10) {
                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    apps.removeAll { $0.id == app.id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(app.name)")
            }
        }
        HStack {
            Spacer()
            Button("Add App…") {
                for app in AppRef.choose() where !apps.contains(app) {
                    apps.append(app)
                }
            }
        }
    }
}

/// Header row used at the top of every feature pane.
struct FeatureHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isOn {
                        Circle().fill(isActive ? Color.green : Color.orange).frame(width: 7, height: 7)
                            .help(isActive ? "Running" : "Waiting for permission")
                    }
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

struct AccessibilityBanner: View {
    let feature: String

    var body: some View {
        SetupBanner(symbol: "hand.raised.fill", tint: .orange, title: "Accessibility needed",
                    message: "\(feature) needs Accessibility access to work.") {
            Button("Grant…") { GrantPanelController.shared.show(.accessibility) }
        }
    }
}
