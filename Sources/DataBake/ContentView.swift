// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI
import SkipSQL

let tableName = "DBTABLE"

/// The local database
let database = try! SQLContext(path: URL.temporaryDirectory.appendingPathComponent("sql.db").path, flags: [.readWrite, .create])

struct ContentView: View {
    @AppStorage("setting") var setting = true
    @State var recordCount = 2
    @State var message: String? = nil

    var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    HStack {
                        Button("Increase Records") {
                            recordCount = (max(recordCount, 1)) * 2
                            do {
                                try database.exec(sql: "CREATE TABLE IF NOT EXISTS \(tableName) (STRING TEXT)")

                                let stmnt = try database.prepare(sql: "INSERT INTO \(tableName) VALUES (?)")
                                let startTime = Date.now
                                try database.transaction {
                                    for _ in 0..<recordCount {
                                        try stmnt.bind(.text(UUID().uuidString), at: 1)
                                    }
                                }
                                let t = Date.now.timeIntervalSince(startTime)
                                self.message = "Inserted \(recordCount) into \(tableName) in \(t)"

                            } catch {
                                self.message = "\(error)"
                            }
                        }
                        Button("Clear Database") {
                            do {
                                recordCount = 1
                                let startTime = Date.now
                                let count = try database.exec(sql: "DELETE FROM \(tableName)")
                                let t = Date.now.timeIntervalSince(startTime)
                                self.message = "Cleared \(count) rows from \(tableName) in \(t)"
                            } catch {
                                self.message = "\(error)"
                            }
                        }
                    }
                    Text(self.message ?? " ").font(.title2)
                    Divider()
                    List {
                        ForEach(Array(0..<recordCount), id: \.self) { i in
                            NavigationLink("Database Record \(i)", value: i)
                        }
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
