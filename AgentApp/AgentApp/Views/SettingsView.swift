import SwiftUI

/// Settings view for configuring application preferences
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Terminal Backend", selection: $settings.terminalBackend) {
                    ForEach(TerminalBackend.allCases, id: \.self) { backend in
                        VStack(alignment: .leading) {
                            Text(backend.rawValue)
                            Text(backend.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(backend)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Text("Shell")
                    Spacer()
                    Text(settings.defaultShell)
                        .foregroundColor(.secondary)
                }

                Toggle("Show backend indicator", isOn: $settings.showTerminalBackendIndicator)
                    .help("Show which terminal backend is active in the terminal tab")
            } header: {
                Text("Terminal")
            } footer: {
                Text("Ghostty provides GPU-accelerated rendering for better performance. SwiftTerm is a fallback option if you experience issues.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
        .navigationTitle("Settings")
    }
}

/// Settings window for use in the app menu
struct SettingsWindowView: View {
    var body: some View {
        SettingsView(settings: AppSettings.shared)
            .padding()
    }
}

// Preview disabled - use Xcode for previews
// #Preview {
//     SettingsView(settings: AppSettings.shared)
// }
