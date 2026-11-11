import SwiftUI

struct ScrollPane: View {
    @ObservedObject var scroll: ScrollModel
    @ObservedObject var permissions: PermissionsModel

    var body: some View {
        Form {
            Section {
                FeatureHeader(symbol: "computermouse.fill", tint: .blue, title: "Smooth Scroll",
                              subtitle: "Smooth, eased scrolling for mouse wheels. Trackpads are left alone.",
                              isOn: $scroll.settings.enabled, isActive: scroll.isActive)
                if scroll.settings.enabled && !permissions.accessibility {
                    AccessibilityBanner(feature: "Smooth Scroll")
                }
            }

            Section("Behavior") {
                Toggle("Smooth scrolling", isOn: $scroll.settings.smooth)
                Toggle("Reverse wheel direction", isOn: $scroll.settings.reverse)
            }

            Section {
                LabeledSlider(title: "Step", value: $scroll.settings.step, range: 20...150, format: { "\(Int($0)) px" })
                LabeledSlider(title: "Speed", value: $scroll.settings.speed, range: 1...4, format: { String(format: "%.1f×", $0) })
                LabeledSlider(title: "Duration", value: $scroll.settings.duration, range: 0.1...0.8,
                              format: { "\(Int(($0 * 1000).rounded())) ms" })
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        let d = ScrollSettings()
                        scroll.settings.step = d.step
                        scroll.settings.speed = d.speed
                        scroll.settings.duration = d.duration
                    }
                }
            } header: {
                Text("Feel")
            }
            .disabled(!scroll.settings.smooth)

            Section {
                AppListEditor(apps: $scroll.settings.exceptions, emptyText: "No exceptions. Apps listed here get raw wheel scrolling.")
            } header: {
                Text("Exceptions")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Smooth Scroll")
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
