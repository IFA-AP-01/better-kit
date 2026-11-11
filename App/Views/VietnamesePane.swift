import SwiftUI

struct VietnamesePane: View {
    @ObservedObject var vietnamese: VietnameseModel
    @ObservedObject var permissions: PermissionsModel

    var body: some View {
        Form {
            Section {
                FeatureHeader(symbol: "character.textbox", tint: .red, title: "Vietnamese Typing",
                              subtitle: "Telex and VNI input powered by the uvie engine.",
                              isOn: $vietnamese.settings.enabled, isActive: vietnamese.isActive)
                if vietnamese.settings.enabled && !permissions.accessibility {
                    AccessibilityBanner(feature: "Vietnamese typing")
                }
            }

            Section {
                Picker("Mode", selection: $vietnamese.settings.vietnameseOn) {
                    Text("Vietnamese").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("Switch with", selection: $vietnamese.settings.hotkey) {
                    ForEach(ModifierHotkey.presets, id: \.self) { key in
                        Text(key.symbols).tag(key)
                    }
                }
                Toggle("Remember the mode for each app", isOn: $vietnamese.settings.rememberPerApp)
            } header: {
                Text("Language")
            } footer: {
                Text("Press and release the modifier keys together to switch between Vietnamese and English.")
            }

            Section("Input") {
                Picker("Input method", selection: $vietnamese.settings.method) {
                    ForEach(InputMethod.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Modern tone placement (oà, uý)", isOn: $vietnamese.settings.modernOrthography)
                Toggle("Keep English words as typed", isOn: $vietnamese.settings.englishOverride)
                if vietnamese.settings.method != .vni {
                    Toggle("Quick Telex (cc → ch, gg → gi…)", isOn: $vietnamese.settings.quickTelex)
                }
            }

            Section {
                AppListEditor(apps: $vietnamese.settings.exclusions, emptyText: "No excluded apps.")
            } header: {
                Text("Always English in")
            }

            Section("Try it") {
                TryTypingField()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vietnamese")
    }
}

private struct TryTypingField: View {
    @State private var text = ""

    var body: some View {
        TextField("Type here, e.g. “tieengs Vieetj”", text: $text, axis: .vertical)
            .lineLimit(2...4)
    }
}
