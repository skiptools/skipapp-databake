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
    func testDataBakeSQL() async throws {
        let db = try DataBakeModel(url: nil)

        let newItem: (Int64) -> (DataItem) = {
            DataItem(id: $0, title: "Item", created: Date.now, contents: "Item contents")
        }

//        XCTAssertEqual(0, try db.queryDataItemCount())
//        try db.insert(items: [newItem(Int64(99))])
//        XCTAssertEqual(1, try db.queryDataItemCount())
//        XCTAssertEqual([Int64(99)], try db.queryIDs())
//        XCTAssertEqual([Int64(99)], db.rowids)
//
//        // insert 901 more rows
//        try db.insert(items: Array((Int64(100)...Int64(1000)).map(newItem)))
//        XCTAssertEqual(902, try db.queryDataItemCount())
//
//        try db.delete(ids: Array(Int64(200)...Int64(800)))
//        XCTAssertEqual(301, db.rowids.count)
//        XCTAssertEqual(301, try db.queryDataItemCount())
//        XCTAssertEqual(200, try db.queryDataItems(where: "id > ?", [.integer(Int64(500))]).count)
//
//        var first = try XCTUnwrap(db.queryDataItems().first)
//        first.title = "NEW TITLE"
//        let qtitle = [SQLValue.text(first.title)]
//        XCTAssertEqual(0, try db.queryDataItems(where: "title = ?", qtitle).count)
//        try db.update(items: [first])
//        XCTAssertEqual(1, try db.queryDataItems(where: "title = ?", qtitle).count)
//
//        var items3 = [newItem(nil), newItem(nil), newItem(nil)]
//        XCTAssertEqual(nil, items3[0].id)
//        XCTAssertEqual(nil, items3[1].id)
//        XCTAssertEqual(nil, items3[2].id)
//        let ids3 = try db.insert(items: items3)
//        // assign the PK
//        for (i, id) in ids3.enumerated() {
//            items3[i].id = id
//        }
//        XCTAssertEqual(1001, items3[0].id)
//        XCTAssertEqual(1002, items3[1].id)
//        XCTAssertEqual(1003, items3[2].id)

        //XCTAssertEqual(200, try db.queryDataItems(where: "id > ?", [.integer(Int64(600))]).count)
    }

    func testDataBakeModel() throws {
        logger.log("running testDataBakeModel")
        XCTAssertEqual(1 + 2, 3, "basic test")

        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("DataBakeModel", testData.testModuleName)
    }

}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
