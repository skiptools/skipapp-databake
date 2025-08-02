import Combine
import DataBakeModel
import SwiftUI

/// Editable detail view of a record.
struct DetailView: View {
    let model: DataBakeModel
    let id: Int64
    @State var dataItem = DataItem(id: 0, title: "", contents: "")
    @Environment(\.dismiss) var dismiss

    init(model: DataBakeModel, id: Int64) {
        self.model = model
        self.id = id
    }

    var body: some View {
        Form {
            TextField("Title", text: $dataItem.title, prompt: Text("Enter title"))
            LabeledValue(label: "Created", value: dataItem.created.formatted())
            LabeledValue(label: "Modified", value: dataItem.modified == nil ? "Never" : dataItem.modified!.formatted())
            TextField("Contents", text: $dataItem.contents, prompt: Text("Enter contents"))
        }
        .navigationTitle("Record \(id)")
        .toolbar {
            Button {
                Task {
                    await saveDataItem()
                }
            } label: {
                Text("Save").bold()
            }
        }
        .disabled(dataItem.id == Int64(0))
        .task {
            await loadDataItem()
        }
    }

    @MainActor private func loadDataItem() async {
        do {
            if let found = try await model.dataItem(id: id) {
                dataItem = found
            } else {
                dismiss()
            }
        } catch {
            logger.log("\(error.localizedDescription)")
            dismiss()
        }
    }

    @MainActor private func saveDataItem() async {
        dataItem.modified = Date.now
        do {
            try await model.update(dataItem)
            dismiss()
        } catch {
            logger.log("\(error.localizedDescription)")
        }
    }
}

struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .bold()
            Spacer()
            Text(value)
        }
    }
}
