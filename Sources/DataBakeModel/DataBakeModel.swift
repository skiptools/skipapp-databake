// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Foundation
import OSLog
import SkipSQL

let logger: Logger = Logger(subsystem: "skip.data.bake.Model", category: "DataBake")

public struct DataItem : Identifiable {
    public static let tableName = "DATA_ITEM"

    public static let columns = ["id", "title", "created", "contents", "rating", "thumbnail"]
    public static var columnNames: String { columns.joined(separator: ", ") }
    public static var columnUpdate: String { columns.joined(separator: " = ?, ") + " = ?" }

    public typealias ID = Int64

    public let id: ID
    public var title: String
    public var created: Date
    public var contents: String
    public var rating: Double?
    public var thumbnail: Data?

    public init(id: ID, title: String, created: Date, contents: String, rating: Double? = nil, thumbnail: Data? = nil) {
        self.id = id
        self.title = title
        self.created = created
        self.contents = contents
        self.rating = rating
        self.thumbnail = thumbnail
    }
}

protocol SQLRow {
//    // Kotlin does not support static requirements in protocols
//    static var tableName: String { get }
//    static var columns: [String] { get }

//    // Kotlin does not support constructors in protocols
//    init(fromCursor statement: SQLStatement, fromIndex: Int32) throws

    /// The SQLValue array for this item in the same order as `columnNames`.
    /// These values will be used for `insert()` and `update()` operations.
    var itemParameters: [SQLValue] { get }
}

extension DataItem : SQLRow {
    /// Initializes from a result set that was selected from `columnNames` from the `fromIndex` offset.
    init(fromCursor statement: SQLStatement, fromIndex: Int32 = 0) throws {
        func fail<T>(_ msg: String) throws -> T {
            throw DataBakeManager.MissingColumnError(errorDescription: "Could not load DataItem column: \(msg)")
        }

        self.id = try statement.value(at: fromIndex + 0).integerValue ?? fail("id")
        self.title = try statement.value(at: fromIndex + 1).textValue ?? fail("title")
        self.created = try statement.value(at: fromIndex + 2).floatValue.flatMap({ Date(timeIntervalSince1970: $0) }) ?? fail("created")
        self.contents = try statement.value(at: fromIndex + 3).textValue ?? fail("contents")
        self.rating = statement.value(at: fromIndex + 4).floatValue
        self.thumbnail = statement.value(at: fromIndex + 5).blobValue
    }

    /// The SQLValue array for this item in the same order as `columnNames`
    var itemParameters: [SQLValue] {
        [
            .integer(id),
            .text(title),
            .float(created.timeIntervalSince1970),
            .text(contents),
            rating.flatMap({ SQLValue.float($0) }) ?? SQLValue.null,
            thumbnail.flatMap({ SQLValue.blob($0) }) ?? SQLValue.null,
        ]
    }
}

// the quoted table name for the DataItem
let QTBL = "\"\(DataItem.tableName)\""

public class DataBakeManager {
    var ctx: SQLContext

    public struct MissingColumnError : LocalizedError {
        public var errorDescription: String?
    }

    public init(in directory: URL?) throws {
        let startTime = Date.now
        let path = directory?.appendingPathComponent("sql.db").path
        let db = try SQLContext(path: path ?? ":memory:", flags: [.readWrite, .create])
        try db.exec(sql: """
        CREATE TABLE IF NOT EXISTS \(QTBL) (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            created FLOAT NOT NULL,
            contents TEXT,
            rating FLOAT,
            thumbnail BLOB
        )
        """)
        let t = Date.now.timeIntervalSince(startTime)
        logger.log("Created database \(path ?? "in-memory") in \(round(t * 1_000.0) / 10_000.0)")
        self.ctx = db
    }

    /// Deletes the items with the given IDs.
    public func delete(ids: [DataItem.ID]) throws {
        return try ctx.exec(sql: "DELETE FROM \(QTBL) WHERE ID IN (\(ids.map(\.description).joined(separator: ",")))")
    }

    /// Updates the items in the database based on their corresponding IDs.
    public func update(items: [DataItem]) throws {
        let sql = "UPDATE \(QTBL) SET " + DataItem.columnUpdate + " WHERE id = ?"
        let stmnt = try ctx.prepare(sql: sql)
        defer { stmnt.close() }
        for item in items {
            try stmnt.update(parameters: item.itemParameters + [SQLValue.integer(item.id)])
        }
    }

    /// Insert new instances of the item into the database.
    public func insert(items: [DataItem]) throws {
        try ctx.transaction {
            let stmnt = try ctx.prepare(sql: "INSERT INTO \(QTBL) (\(DataItem.columnNames)) VALUES (?, ?, ?, ?, ?, ?)")
            defer { stmnt.close() }
            for item in items {
                try stmnt.update(parameters: item.itemParameters)
            }
        }
    }

    /// Returns the total number of rows for a table.
    public func queryDataItemCount() throws -> Int64? {
        try ctx.prepare(sql: "SELECT COUNT(*) FROM \(QTBL)").nextValues(close: true)?.first?.integerValue
    }

    public func queryIDs(limit: Int64? = nil) throws -> [DataItem.ID] {
        let stmnt = try ctx.prepare(sql: "SELECT id FROM \(QTBL)")
        defer { stmnt.close() }
        var ids: [DataItem.ID] = []
        while try stmnt.next() {
            ids.append(stmnt.integer(at: 0))
        }
        return ids
    }

    /// Fetches the items with the corresponding IDs.
    ///
    ///  Note that the order of the returned items is unrelated to the order of the `ids` parameter, nor is the returned array guaranteed to contains all the identifiers, since missing elements are not detected nor considered an error.
    public func fetch(ids: [DataItem.ID]) throws -> [DataItem] {
        try queryDataItems(where: "id IN (" + ids.map({ _ in "?" }).joined(separator: ",") + ")", ids.map({ SQLValue.integer($0) }))
    }

    public func queryDataItems(where whereClause: String? = nil, _ values: [SQLValue] = []) throws -> [DataItem] {
        var sql = "SELECT \(DataItem.columnNames) FROM \(QTBL)"
        if let whereClause = whereClause {
            sql += " WHERE " + whereClause
        }
        let stmnt = try ctx.prepare(sql: sql)
        try stmnt.bind(parameters: values)
        defer { stmnt.close() }
        var items: [DataItem] = []
        while try stmnt.next() {
            items.append(try DataItem(fromCursor: stmnt))
        }

        return items
    }
}

