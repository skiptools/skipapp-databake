// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI

struct SettingsView: View {
    @AppStorage("setting") var setting = true

    var body: some View {
        Form {
            Toggle("Option", isOn: $setting)
        }
        .navigationTitle("Settings")
    }
}
