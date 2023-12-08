// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

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
