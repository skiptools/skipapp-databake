// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI

struct ContentView: View {
    @AppStorage("setting") var setting = true
    @State var recordCount = 2

    var body: some View {
        TabView {
            NavigationStack {
                Button("Increase Records") {
                    recordCount *= 2
                }
                List {
                    ForEach(1..<recordCount) { i in
                        NavigationLink("Database Record \(i)", value: i)
                    }
                }
                .navigationTitle("\(recordCount) records")
                .navigationDestination(for: Int.self) { i in
                    Text("Database Record \(i)")
                        .font(.title)
                        .navigationTitle("Record \(i)")
                }
            }
            .tabItem { Label("Database", systemImage: "list.bullet") }

            Form {
                Text("Settings")
                    .font(.largeTitle)
                Toggle("Option", isOn: $setting)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
