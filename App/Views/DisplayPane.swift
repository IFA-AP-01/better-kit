import SwiftUI

struct DisplayPane: View {
    @ObservedObject var display: DisplayModel

    var body: some View {
        Form {
            Section {
                FeatureHeader(symbol: "display", tint: .purple, title: "HiDPI",
                              subtitle: "Render at 2× and scale down, so text on a 1080p panel looks smooth.",
                              isOn: $display.settings.hiDPIEnabled, isActive: display.hiDPIActive)
                if let error = display.hiDPIError {
                    SetupBanner(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "HiDPI", message: error) {
                        Button("Retry") { display.applyHiDPI(force: true) }
                    }
                }
            }

            Section("HiDPI") {
                Picker("Display", selection: Binding(get: { display.target?.key ?? "" },
                                                     set: { display.settings.targetDisplay = $0.isEmpty ? nil : $0 })) {
                    ForEach(display.displays.filter { !$0.isBuiltin }) { info in
                        Text(info.name).tag(info.key)
                    }
                    if display.displays.allSatisfy(\.isBuiltin) {
                        Text("No external display").tag("")
                    }
                }
                Picker("Looks like", selection: $display.settings.looksLike) {
                    ForEach(ResolutionChoice.choices) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                LabeledContent("Status") {
                    if display.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(statusText).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if display.ddcAvailable {
                    LabeledSlider(title: "Brightness", value: Binding(get: { display.brightness }, set: { display.setBrightness($0) }),
                                  range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" })
                    LabeledSlider(title: "Contrast", value: Binding(get: { display.contrast }, set: { display.setContrast($0) }),
                                  range: 0...1, format: { "\(Int(($0 * 100).rounded()))%" })
                } else {
                    Toggle("Software dimming", isOn: $display.settings.softwareDimming)
                    if display.settings.softwareDimming {
                        LabeledSlider(title: "Brightness", value: Binding(get: { display.brightness }, set: { display.setBrightness($0) }),
                                      range: 0.1...1, format: { "\(Int(($0 * 100).rounded()))%" })
                    }
                }
                HStack {
                    Spacer()
                    Button("Detect DDC Again") { display.probeDDC() }
                }
            } header: {
                Text("Brightness")
            } footer: {
                Text(display.ddcAvailable
                     ? "Controls the monitor's own backlight over DDC/CI."
                     : "This monitor did not answer DDC/CI on this port. Software dimming lowers the image level instead.")
            }

            Section {
                Picker("Font smoothing", selection: $display.settings.fontSmoothing) {
                    Text("System default").tag(Int?.none)
                    Text("Off").tag(Int?.some(0))
                    Text("Light").tag(Int?.some(1))
                    Text("Medium").tag(Int?.some(2))
                    Text("Strong").tag(Int?.some(3))
                }
            } header: {
                Text("Text")
            } footer: {
                Text("Apps pick up the change after they are reopened.")
            }

            Section("Connected displays") {
                ForEach(display.displays) { info in
                    LabeledContent(info.name) {
                        Text("\(Int(info.pointSize.width))×\(Int(info.pointSize.height)) · \(Int(info.pixelSize.width))×\(Int(info.pixelSize.height)) px · \(Int(info.refreshRate.rounded())) Hz")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .onAppear { display.refreshDisplays() }
    }

    private var statusText: String {
        if display.hiDPIActive {
            return "On · rendering \(display.settings.looksLike.width * 2)×\(display.settings.looksLike.height * 2)"
        }
        return display.settings.hiDPIEnabled ? "Waiting" : "Off"
    }
}
