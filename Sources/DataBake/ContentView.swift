// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI
import SkipSQL

let tableName = "DBTABLE"

/// The local database
let database = try! createSQLContext()

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
        try database.transaction {
            let stmnt = try database.prepare(sql: "INSERT INTO \(tableName) VALUES (?)")
            for _ in 0..<recordCount {
                try stmnt.update([.text(UUID().uuidString)])
            }
        }
        let t = Date.now.timeIntervalSince(startTime)
        msg("Inserted \(recordCount) into \(tableName) in \(round(t * 1_000.0) / 1_000.0)")
    }

    @MainActor func msg(_ message: String) {
        logger.info("\(message)")
        self.message = message
    }

    @MainActor func clearDatabase() throws {
        let startTime = Date.now
        let count = try database.mutex {
            defer { self.recordCount = 0 }
            return try database.exec(sql: "DELETE FROM \(tableName)")
        }
        let t = Date.now.timeIntervalSince(startTime)
        msg("Cleared \(count) rows from \(tableName) in \(round(t * 1_000.0) / 10_000.0)")
    }
}

func createSQLContext(in directory: URL = .temporaryDirectory) throws -> SQLContext {
    let startTime = Date.now
    let path = directory.appendingPathComponent("sql.db").path
    let db = try SQLContext(path: path, flags: [.readWrite, .create])
    try db.mutex {
        try db.exec(sql: "PRAGMA journal_mode=DELETE") // disable WAL for performance
        try db.exec(sql: "CREATE TABLE IF NOT EXISTS \(tableName) (STRING TEXT)")
    }
    let t = Date.now.timeIntervalSince(startTime)
    logger.log("Created database \(path) in \(round(t * 1_000.0) / 10_000.0)")
    return db
}
