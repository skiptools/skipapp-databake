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
