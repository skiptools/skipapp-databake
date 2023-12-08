// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Combine
import DataBakeModel
import SwiftUI

struct DetailView: View {
    let model: DataBakeModel
    let id: Int64
    @State var dataItem: DataItem?

    init(model: DataBakeModel, id: Int64) {
        self.model = model
        self.id = id
    }

    var body: some View {
        //~~~
        Text("ID: \(id)")
    }
}
