// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI
import OSLog
import SkipSQL
import DataBakeModel


/// The local database
let db = try! DataBakeManager(in: URL.temporaryDirectory)

public struct ContentView: View {
    @AppStorage("setting") var setting = true
    @State var recordCount = 2
    @State var message: String? = nil

    public init() {
    }
    
    public var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    HStack {
                        Button("Increase Records") {
                            recordCount = (max(recordCount, 1)) * 2
                            Task.detached {
                                do {
                                    try await insert(rows: recordCount)
                                } catch {
                                    await msg("\(error)")
                                }
                            }
                        }
                        Button("Clear Database") {
                            Task.detached {
                                do {
                                    try await clearDatabase()
                                } catch {
                                    await msg("\(error)")
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Divider()
                    Text(self.message ?? " ").font(.caption)
                    Divider()

                    List(0..<recordCount, id: \.self) { i in
                        //ForEach(0..<recordCount, id: \.self) { i in
                            NavigationLink("Database Record \(i)", value: i)
                        //}
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

    @MainActor func insert(rows: Int) throws {
        let startTime = Date.now
        try db.insert(items: Array(Int64(0)..<Int64(rows)).map({ i in
            DataItem(id: i, title: "Row #(i)", created: .now, contents: "Row content")
        }))
        let t = Date.now.timeIntervalSince(startTime)
        msg("Inserted \(recordCount) in \(round(t * 1_000.0) / 1_000.0)")
    }

    @MainActor func msg(_ message: String) {
        //logger.info("\(message)")
        self.message = message
    }

    @MainActor func clearDatabase() throws {
        let startTime = Date.now
        let ids = try db.queryIDs()
        try db.delete(ids: ids)
        let t = Date.now.timeIntervalSince(startTime)
        msg("Cleared \(ids.count) rows in \(round(t * 1_000.0) / 10_000.0)")
    }
}
