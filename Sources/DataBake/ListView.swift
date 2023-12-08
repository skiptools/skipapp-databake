// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Combine
import DataBakeModel
import SwiftUI

struct ListView: View {
    let model: DataBakeModel
    @StateObject var viewModel: ListViewModel
    @State var isActionsPresented = false

    init(model: DataBakeModel) {
        self.model = model
        logger.log("CREATING NEW STATE OBJECT ===========") //~~~
        _viewModel = StateObject<ListViewModel>(wrappedValue: ListViewModel(model: model))
    }

    var body: some View {
        VStack {
            if let previews = viewModel.previews {
                List {
                    Text(viewModel.message)
                        .font(.caption)
                    ForEach(previews) { preview in
                        NavigationLink(value: preview.id) {
                            DataItemPreviewView(preview: preview)
                        }
                    }
                    .onDelete {
                        viewModel.delete(at: $0)
                    }
                }
                .searchable(text: $viewModel.searchString)
                .navigationTitle(previews.count == 1 ? "1 Record" : "\(previews.count) Records")
                .navigationDestination(for: Int64.self) {
                    DetailView(model: model, id: $0)
                }
            } else {
                VStack {
                    ProgressView()
                    Text(viewModel.message)
                        .font(.caption)
                }
                .navigationTitle("Loading…")
            }
        }
        .toolbar {
            Button {
                isActionsPresented = true
            } label: {
                Image(systemName: "ellipsis")
            }
            .disabled(viewModel.previews == nil)
        }
        .confirmationDialog("Actions", isPresented: $isActionsPresented) {
            Button("Insert 1") {
                viewModel.insert(count: 1)
            }
            Button("Insert 1,000") {
                viewModel.insert(count: 1_000)
            }
            Button("Insert 10,000") {
                viewModel.insert(count: 10_000)
            }
            Button("Reset", role: .destructive) {
                viewModel.reset()
            }
        }
    }
}

/// View model for list view.
@MainActor class ListViewModel: ObservableObject {
    let model: DataBakeModel
    @Published var previews: [DataItemPreview]?
    @Published var message = ""
    @Published var searchString = ""
    private var subscriptions: Set<AnyCancellable> = []

    init(model: DataBakeModel) {
        self.model = model
        updatePreviews(titlePrefix: "")

        // Update our previews as the user searches
        $searchString
            .dropFirst() // Initial property value
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .sink { [weak self] in
                logger.log("GOT NEW SEARCH STRING ===========") //~~~
                self?.updatePreviews(titlePrefix: $0)
            }
            .store(in: &subscriptions)

        // Subscribe to updates
        NotificationCenter.default.publisher(for: .dataItemsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                logger.log("GOT NEW NOTIFICATION ===========") //~~~
                if let change = $0.object as? DataItemsChange {
                    self?.updatePreviews(change: change)
                }
            }
            .store(in: &subscriptions)
    }

    /// Helper to perform a given async model operation and update our message.
    private func perform(verb: String, operation: @escaping () async throws -> Int) {
        Task {
            do {
                let start = Date.now
                let count = try await operation()
                let duration = Int((Date.now.timeIntervalSince1970 - start.timeIntervalSince1970) * 1_000)
                message = count == 1 ? "\(verb) 1 record in \(duration)ms" : "\(verb) \(count) records in \(duration)ms"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func insert(count: Int) {
        guard count > 0 else {
            return
        }
        message = "Inserting…"
        perform(verb: "Inserted") {
            // Insert in batches so that the user gets feedback
            var remaining = count
            while remaining > 0 {
                let batchCount = min(remaining, 100)
                let dataItems = (0..<batchCount).map { _ in
                    var title = UUID().uuidString
                    if let dashIndex = title.firstIndex(of: "-") {
                        title = String(title.prefix(upTo: dashIndex))
                    }
                    return DataItem(title: title, contents: "Initial contents")
                }
                try await self.model.insert(dataItems)
                remaining -= batchCount
            }
            return count
        }
    }

    func delete(at indexes: IndexSet) {
        guard let previews else {
            return
        }
        let ids = indexes.map { previews[$0].id }
        perform(verb: "Deleted") {
            return try await self.model.deleteDataItems(ids: ids)
        }
    }

    func reset() {
        perform(verb: "Cleared") {
            return try await self.model.deleteDataItems()
        }
    }

    private func updatePreviews(titlePrefix: String) {
        perform(verb: "Found") {
            self.previews = try await self.model.dataItemPreviews(titlePrefix: self.searchString)
            return self.previews?.count ?? 0
        }
    }

    private func updatePreviews(change: DataItemsChange) {
        guard let previews else {
            return
        }
        // Nil deletes set means all were deleted
        guard change.deletes != nil else {
            self.previews = []
            return
        }

        var updatedPreviews = previews
        if !change.updates.isEmpty || change.deletes?.isEmpty == false {
            var removeIndexes = IndexSet()
            for i in 0..<previews.count {
                if let (_, new) = change.updates[previews[i].id] {
                    updatedPreviews[i] = new.preview
                } else if let deletes = change.deletes, deletes.contains(previews[i].id) {
                    removeIndexes.insert(i)
                }
            }
            updatedPreviews.remove(atOffsets: removeIndexes)
        }
        for insert in change.inserts {
            if insert.title.hasPrefix(searchString) {
                updatedPreviews.append(insert.preview)
            }
        }
        self.previews = updatedPreviews
    }
}


struct DataItemPreviewView : View {
    let preview: DataItemPreview

    var body: some View {
        HStack {
            Text(String(describing: preview.id))
                .font(.caption)
                .bold()
            Text(preview.title)
        }
    }
}



//func commandButtonRow() -> some View {
//    VStack {
//        HStack {
//            actionButton("+1") {
//                try createItems(count: 1)
//            }
//            actionButton("+1K") {
//                try createItems(count: 1_000)
//            }
//            actionButton("+10K") {
//                try createItems(count: 10_000)
//            }
//        }
//
//        HStack {
//            actionButton("Refresh") {
//                try db.reload()
//            }
//            actionButton("Shuffle") {
//                try db.reload(orderBy: "RANDOM()")
//            }
//            actionButton("Reset") {
//                try db.delete(ids: db.queryIDs())
//            }
//        }
//    }
//    .buttonStyle(.borderedProminent)
//}
//
//func actionButton(_ title: String, action: @escaping () throws -> ()) -> some View {
//    Button(title) {
//        let startTime = Date.now
//        do {
//            try withAnimation {
//                try action()
//            }
//            msg("Action \"\(title)\" on \(db.rowids.count) rows in \(startTime.durationToNow)")
//        } catch {
//            msg("Error \"\(title)\": " + String(describing: error))
//        }
//    }
//    .frame(minWidth: 140.0, maxWidth: 140.0)
//}
//
//
//func createItems(count: Int) throws {
//    let items = Array((0..<count).map({ _ in
//        DataItem(title: "New Item", created: .now, contents: UUID().uuidString)
//    }))
//
//    if items.count <= 1 {
//        try db.insert(items: items)
//    } else {
//        // when there is more than one ID, we add them in the background to demonstrate concurrent database access
//        Task.detached {
//            let startTime = Date.now
//            let blockSize = count / 100
//            for i in stride(from: 0, to: items.count, by: blockSize) {
//                let itemBlock = Array(items[i..<min(i+blockSize, items.count)])
//
//                await MainActor.run {
//                    insert(items: itemBlock)
//                }
//            }
//            await msg("Insert \(items.count) rows in \(startTime.durationToNow)")
//        }
//    }
//}
//
//@MainActor func insert(items: [DataItem]) {
//    do {
//        let startTime = Date.now
//        for item in items {
//            try db.insert(items: [item])
//        }
//        msg("Insert \(items.count) rows in \(startTime.durationToNow)")
//    } catch {
//        msg("Error inserting: " + String(describing: error))
//    }
//}
//
//func msg(_ message: String) {
//    logger.info("\(message)")
//    self.message = message
//}
//
//@ViewBuilder func dataItemRow(rowid: DataItem.RowID) -> some View {
//    NavigationLink(value: rowid) {
//        HStack {
//            // if-let doesn't work with ViewBuilder yet
//            let item = (try? db.fetch(ids: [rowid]).first)
//            if item != nil {
//                Text(rowid.description)
//                    .font(.caption)
//                    .bold()
//                Text("\(item!.title)")
//                //Text("\(item!.created.description)")
//            }
//        }
//    }
//}
//
//@ViewBuilder func dataItemDestination(rowid: DataItem.RowID) -> some View {
//   HStack {
//       // if-let doesn't work with ViewBuilder yet
//       let item = (try? db.fetch(ids: [rowid]).first)!
//       Text("\(item.title)")
//           .font(.title)
//       Text("\(item.created.description)")
//           .font(.title2)
//   }
//}
//}
