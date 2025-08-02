import XCTest
import OSLog
import Foundation
@testable import DataBakeModel
import SkipSQL

let logger: Logger = Logger(subsystem: "DataBakeModel", category: "Tests")

@available(macOS 13, *)
final class DataBakeModelTests: XCTestCase {
    func testDataBakeModel() async throws {
        let db = try DataBakeModel(url: nil)
        var items = try db.insert([DataItem(title: "Item", contents: "Item contents")])
        XCTAssertEqual(1, items.first?.id)

        var previews = items.map(\.preview)
        XCTAssertEqual("Item", previews.first?.title)

        previews = try db.dataItemPreviews()
        XCTAssertEqual(1, previews.count)

        items[0].title = "XXX"
        try db.update(items[0])

        previews = try db.dataItemPreviews(titlePrefix: "X")
        XCTAssertEqual(1, previews.count)
    }
}
