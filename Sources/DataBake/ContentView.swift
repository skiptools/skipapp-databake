// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import SwiftUI
import OSLog
import SkipSQL
import DataBakeModel

public struct ContentView: View {
    @AppStorage("setting") var setting = true
    @State var message: String? = nil
    @ObservedObject var db: DataBakeManager

    public init(db: DataBakeManager) {
        self.db = db
    }

    public var body: some View {
        TabView {
            NavigationStack {
                VStack {
                    List($db.rowids, id: \.self, editActions: [.delete]) { id in
                        dataItemRow(rowid: id.wrappedValue)
                    }
                    .navigationTitle("\(db.rowids.count) records")
                    .navigationDestination(for: DataItem.RowID.self, destination: dataItemDestination)
                    messageRow()
                    commandButtonRow()
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

    func commandButtonRow() -> some View {
        VStack {
            HStack {
                actionButton("+1") {
                    try createItems(count: 1)
                }
                actionButton("+1K") {
                    try createItems(count: 1_000)
                }
                actionButton("+10K") {
                    try createItems(count: 10_000)
                }
            }

            HStack {
                actionButton("Refresh") {
                    try db.reload()
                }
                actionButton("Shuffle") {
                    try db.reload(orderBy: "RANDOM()")
                }
                actionButton("Reset") {
                    try db.delete(ids: db.queryIDs())
                }
            }
        }
        .buttonStyle(.borderedProminent)
    }

    func actionButton(_ title: String, action: @escaping () throws -> ()) -> some View {
        Button(title) {
            let startTime = Date.now
            do {
                try withAnimation {
                    try action()
                }
                msg("Action \"\(title)\" on \(db.rowids.count) rows in \(startTime.durationToNow)")
            } catch {
                msg("Error \"\(title)\": " + String(describing: error))
            }
        }
        .frame(minWidth: 140.0, maxWidth: 140.0)
    }

    @ViewBuilder func messageRow() -> some View {
        //Divider()
        Text(self.message ?? " ")
            .font(.caption)
        //Divider()
    }

    func createItems(count: Int) throws {
        let items = Array((0..<count).map({ _ in
            DataItem(title: "New Item", created: .now, contents: UUID().uuidString)
        }))

        if items.count <= 1 {
            try db.insert(items: items)
        } else {
            // when there is more than one ID, we add them in the background to demonstrate concurrent database access
            Task.detached {
                let startTime = Date.now
                let blockSize = count / 100
                for i in stride(from: 0, to: items.count, by: blockSize) {
                    let itemBlock = Array(items[i..<min(i+blockSize, items.count)])

                    await MainActor.run {
                        insert(items: itemBlock)
                    }
                }
                await msg("Insert \(items.count) rows in \(startTime.durationToNow)")
            }
        }
    }

    @MainActor func insert(items: [DataItem]) {
        do {
            let startTime = Date.now
            for item in items {
                try db.insert(items: [item])
            }
            msg("Insert \(items.count) rows in \(startTime.durationToNow)")
        } catch {
            msg("Error inserting: " + String(describing: error))
        }
    }

    func msg(_ message: String) {
        logger.info("\(message)")
        self.message = message
    }

    @ViewBuilder func dataItemRow(rowid: DataItem.RowID) -> some View {
        NavigationLink(value: rowid) {
            HStack {
                // if-let doesn't work with ViewBuilder yet
                let item = (try? db.fetch(ids: [rowid]).first)
                if item != nil {
                    Text(rowid.description)
                        .font(.caption)
                        .bold()
                    Text("\(item!.title)")
                    //Text("\(item!.created.description)")
                }
            }
        }
    }

    @ViewBuilder func dataItemDestination(rowid: DataItem.RowID) -> some View {
       HStack {
           // if-let doesn't work with ViewBuilder yet
           let item = (try? db.fetch(ids: [rowid]).first)!
           Text("\(item.title)")
               .font(.title)
           Text("\(item.created.description)")
               .font(.title2)
       }
    }
}
