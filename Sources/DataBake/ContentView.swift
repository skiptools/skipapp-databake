// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import DataBakeModel
import SwiftUI

/// Application UI scaffold.
struct ContentView: View {
    let model: DataBakeModel
    
    var body: some View {
        TabView {
            NavigationStack {
                ListView(model: model)
            }
            .tabItem { Label("Database", systemImage: "list.bullet") }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
