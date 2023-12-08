// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Combine
import DataBakeModel
import SwiftUI

/// Searchable list of records.
struct ListView: View {
    let model: DataBakeModel
    @StateObject var viewModel: ListViewModel
    @State var isActionsPresented = false
    @AppStorage("reverseSort") var reverseSort = false

    init(model: DataBakeModel) {
        self.model = model
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
        // For iOS 17+ we could get rid of .onAppear and use the new .onChange that fires on initial value too
        .onAppear {
            viewModel.updatePreviews(reverseSort: reverseSort)
        }
        .onChange(of: reverseSort) {
            viewModel.updatePreviews(reverseSort: $0)
        }
    }
}

/// View model for list view.
@MainActor class ListViewModel: ObservableObject {
    let model: DataBakeModel
    @Published private(set) var previews: [DataItemPreview]?
    @Published private(set) var message = ""
    @Published var searchString = ""
    private var reverseSort = false
    private var subscriptions: Set<AnyCancellable> = []
    private var batching = false

    init(model: DataBakeModel) {
        self.model = model
        updatePreviews(titlePrefix: "")

        // Update our previews as the user searches
        $searchString
            .dropFirst() // Initial property value
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.updatePreviews(titlePrefix: $0)
            }
            .store(in: &subscriptions)

        // Subscribe to updates
        NotificationCenter.default.publisher(for: .dataItemsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
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
            let batchSize = 100
            self.batching = count > batchSize
            var remaining = count
            while remaining > 0 {
                let batchCount = min(remaining, batchSize)
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
            self.batching = false
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

    func updatePreviews(reverseSort: Bool) {
        self.reverseSort = reverseSort
        updatePreviews(titlePrefix: searchString)
    }

    private func updatePreviews(titlePrefix: String) {
        perform(verb: "Found") {
            self.previews = try await self.model.dataItemPreviews(titlePrefix: self.searchString, descending: self.reverseSort)
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
        let inserts = change.inserts.filter { $0.title.hasPrefix(searchString) }.map { $0.preview }
        if reverseSort {
            updatedPreviews = inserts.reversed() + updatedPreviews
        } else {
            updatedPreviews += inserts
        }
        // Don't animate if batching because the successive animations make the UI unresponsive
        if batching {
            self.previews = updatedPreviews
        } else {
            withAnimation { self.previews = updatedPreviews }
        }
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
