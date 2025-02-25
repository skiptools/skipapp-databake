import SwiftUI

/// Application settings.
struct SettingsView: View {
    @AppStorage("reverseSort") var reverseSort = false

    var body: some View {
        Form {
            Toggle("Sort newest to oldest", isOn: $reverseSort)
        }
        .navigationTitle("Settings")
    }
}
