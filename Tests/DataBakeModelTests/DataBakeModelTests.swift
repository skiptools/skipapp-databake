// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import XCTest
import OSLog
import Foundation
@testable import DataBakeModel
import SkipSQL

let logger: Logger = Logger(subsystem: "DataBakeModel", category: "Tests")

@available(macOS 13, *)
final class DataBakeModelTests: XCTestCase {
    func testDataBakeModel() throws {
        logger.log("running testDataBakeModel")
        XCTAssertEqual(1 + 2, 3, "basic test")
        
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("DataBakeModel", testData.testModuleName)
    }

    func testDataBakeSQL() async throws {
        let mkitem: (Int64) -> (DataItem) = {
            DataItem(id: $0 as Int64, title: "Item", created: Date.now, contents: "Item contents", rating: nil, thumbnail: nil)
        }

        let db = try DataBakeManager(in: nil)
        XCTAssertEqual(0, try db.queryDataItemCount())
        try db.insert(items: [mkitem(Int64(99))])
        XCTAssertEqual(1, try db.queryDataItemCount())
        XCTAssertEqual([Int64(99)], try db.queryIDs())

        // insert 901 more rows
        try db.insert(items: Array((Int64(100)...Int64(1000)).map(mkitem)))
        XCTAssertEqual(902, try db.queryDataItemCount())

        try db.delete(ids: Array(Int64(200)...Int64(800)))
        XCTAssertEqual(301, try db.queryDataItemCount())
        XCTAssertEqual(200, try db.queryDataItems(where: "id > ?", [.integer(Int64(500))]).count)

        var first = try XCTUnwrap(db.queryDataItems().first)
        first.title = "NEW TITLE"
        XCTAssertEqual(0, try db.queryDataItems(where: "title = ?", [SQLValue.text(first.title)]).count)
        try db.update(items: [first])
        XCTAssertEqual(1, try db.queryDataItems(where: "title = ?", [SQLValue.text(first.title)]).count)

        //XCTAssertEqual(200, try db.queryDataItems(where: "id > ?", [.integer(Int64(600))]).count)
    }
}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
