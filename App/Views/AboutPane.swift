import SwiftUI

struct AboutPane: View {
    @ObservedObject var updates: UpdateCoordinator
    @ObservedObject var whatsNew: WhatsNewTracker

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BetterKit").font(.title2.bold())
                        Text("Version \(whatsNew.version) (\(build))").foregroundStyle(.secondary)
                        Text("Smooth scroll, HiDPI, Vietnamese typing and fan control in one menu bar app.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Updates") {
                HStack {
                    Button(updates.updateAvailable ? "Update to \(updates.latestVersion)…" : "Check for Updates…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                    Spacer()
                    Button("What's New") { whatsNew.show() }
                }
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }))
                    .disabled(!updates.isEnabled)
                if !updates.isEnabled {
                    Text("Updates are not configured in this build.").font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Credits") {
                Link("uvie-rs — Vietnamese input engine (MIT/Apache-2.0)", destination: URL(string: "https://github.com/uvie-project/uvie-rs")!)
                Link("Fandy — fan control reference (MIT)", destination: URL(string: "https://github.com/NidaleNieve/Fandy_MacOS")!)
                Link("Mos — smooth scrolling reference", destination: URL(string: "https://github.com/Caldis/Mos")!)
                Link("Sparkle — software updates", destination: URL(string: "https://sparkle-project.org")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
