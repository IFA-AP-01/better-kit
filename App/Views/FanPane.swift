import SwiftUI

struct FanPane: View {
    @ObservedObject var fan: FanModel
    @ObservedObject var helper: FanHelperClient

    var body: some View {
        Form {
            Section("Fans") {
                ForEach(fan.fans) { reading in
                    FanRow(reading: reading)
                }
            }

            Section {
                if helper.state != .enabled {
                    SetupRow(symbol: "lock.shield", title: "Fan helper",
                             detail: helper.state == .requiresApproval
                                ? "Approve BetterKit under Login Items › Allow in the Background."
                                : "Changing fan speed needs a small privileged helper. Reading works without it.",
                             state: .required,
                             actionTitle: helper.state == .requiresApproval ? "APPROVE" : "INSTALL",
                             action: { helper.register() })
                }
                Picker("Control", selection: $fan.settings.preset) {
                    ForEach(FanPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(helper.state != .enabled)

                switch fan.settings.preset {
                case .automatic:
                    Text("macOS controls the fans.").foregroundStyle(.secondary)
                case .constant:
                    LabeledSlider(title: "Speed", value: $fan.settings.constantLevel, range: 0...1, format: { level in
                        guard let f = fan.fans.first else { return "" }
                        return "\(Int(f.minimum + level * (f.maximum - f.minimum))) rpm"
                    })
                case .curve:
                    Picker("Sensor", selection: $fan.settings.curveSensor) {
                        Text("Hottest CPU core").tag(String?.none)
                        ForEach(fan.sensors) { s in
                            Text(s.name).tag(String?.some(s.key))
                        }
                    }
                    LabeledSlider(title: "Start at", value: $fan.settings.curveLow, range: 30...80, format: { "\(Int($0)) °C" })
                    LabeledSlider(title: "Full speed at", value: $fan.settings.curveHigh, range: 50...105, format: { "\(Int($0)) °C" })
                    if let t = fan.curveTemperature {
                        LabeledContent("Now") { Text(String(format: "%.0f °C", t)).monospacedDigit() }
                    }
                }
                if let error = fan.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("Control")
            } footer: {
                Text("Fans return to automatic when BetterKit quits or crashes.")
            }

            Section("Sensors") {
                ForEach(fan.sensors) { sensor in
                    LabeledContent(sensor.name) {
                        Text(String(format: "%.0f °C", sensor.value))
                            .monospacedDigit()
                            .foregroundStyle(sensor.value > 85 ? .red : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Fans")
        .onAppear {
            helper.refresh()
            fan.poll()
        }
    }
}

private struct FanRow: View {
    let reading: FanReading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(reading.name, systemImage: "fan")
                if reading.manual {
                    Text("Manual").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Text("\(Int(reading.actual)) rpm").monospacedDigit()
            }
            ProgressView(value: progress)
            Text("Min \(Int(reading.minimum)) · Max \(Int(reading.maximum)) rpm")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var progress: Double {
        guard reading.maximum > 0 else { return 0 }
        return min(max(reading.actual / reading.maximum, 0), 1)
    }
}
