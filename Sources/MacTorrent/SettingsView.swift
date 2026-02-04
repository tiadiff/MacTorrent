import SwiftUI

struct SettingsView: View {
    @AppStorage("stopSeedingOnCompletion") private var stopSeedingOnCompletion = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Stop seeding when download completes", isOn: $stopSeedingOnCompletion)
                    .help("Automatically pause torrents when they reach 100% progress")
            } header: {
                Text("Automation")
            } footer: {
                Text("If enabled, torrents will be paused immediately after finishing the download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
    }
}

#Preview {
    SettingsView()
}
