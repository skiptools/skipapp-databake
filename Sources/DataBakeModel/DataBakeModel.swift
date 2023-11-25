// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Foundation
import OSLog
import Observation
import SkipSQL

let logger: Logger = Logger(subsystem: "skip.data.bake.Model", category: "DataBake")

public struct DataItem : Identifiable, Codable, Hashable, Sendable {
    /// The primary key type is an Int64
    public typealias RowID = Int64

    public var id: RowID?
    public var title: String
    public var created: Date
    public var modified: Date?
    public var contents: String
    public var rating: Double?
    public var thumbnail: Data?

    public init(id: RowID? = nil, title: String, created: Date, modified: Date? = nil, contents: String, rating: Double? = nil, thumbnail: Data? = nil) {
        self.id = id
        self.title = title
        self.created = created
        self.modified = modified
        self.contents = contents
        self.rating = rating
        self.thumbnail = thumbnail
    }

    public enum CodingKeys : String, CodingKey, CaseIterable, SQLColumn {
        case id
        case title
        case created
        case modified
        case contents
        case rating
        case thumbnail

        /// The column name for this key
        public var columnName: String {
            // we just re-use the same underlying name as the key
            rawValue
        }

        /// The SQL DDL for this column
        public var ddl: String {
            switch self {
            case .id: return "INTEGER PRIMARY KEY"
            case .title: return "TEXT NOT NULL"
            case .created: return "FLOAT NOT NULL"
            case .modified: return "FLOAT"
            case .contents: return "TEXT"
            case .rating: return "FLOAT"
            case .thumbnail: return "BLOB"
            }
        }
    }
}

protocol SQLColumn {
    var columnName: String { get }
    var ddl: String { get }
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
    public static let tableName = "DATA_ITEM"

    public static let columns = DataItem.CodingKeys.allCases.map(\.columnName)

    public static var columnNames: String {
        columns.joined(separator: ", ")
    }

    public static var columnUpdate: String {
        columns.joined(separator: " = ?, ") + " = ?"
    }

    /// The SQL insert statement for a row representing this item
    public static var insertSQL: String {
        "INSERT INTO \(QTBL) (\(columnNames)) VALUES (\(columns.map({ _ in "?" }).joined(separator: ", ")))"
    }

    /// Initializes from a result set that was selected from `columnNames` from the `fromIndex` offset.
    init(fromCursor statement: SQLStatement, fromIndex: Int32 = 0) throws {
        func fail<T>(_ msg: String) throws -> T {
            throw MissingColumnError(errorDescription: "Could not load DataItem column: \(msg)")
        }

        self.id = try statement.value(at: fromIndex + 0).integerValue ?? fail("id")
        self.title = try statement.value(at: fromIndex + 1).textValue ?? fail("title")
        self.created = try statement.value(at: fromIndex + 2).floatValue.flatMap({ Date(timeIntervalSince1970: $0) }) ?? fail("created")
        self.modified = statement.value(at: fromIndex + 3).floatValue.flatMap({ Date(timeIntervalSince1970: $0) })
        self.contents = try statement.value(at: fromIndex + 4).textValue ?? fail("contents")
        self.rating = statement.value(at: fromIndex + 5).floatValue
        self.thumbnail = statement.value(at: fromIndex + 6).blobValue
    }

    /// The SQLValue array for this item in the same order as `columnNames`
    var itemParameters: [SQLValue] {
        [
            id.flatMap({ SQLValue.integer($0) }) ?? SQLValue.null,
            .text(title),
            .float(created.timeIntervalSince1970),
            modified.flatMap({ SQLValue.float($0.timeIntervalSince1970) }) ?? SQLValue.null,
            .text(contents),
            rating.flatMap({ SQLValue.float($0) }) ?? SQLValue.null,
            thumbnail.flatMap({ SQLValue.blob($0) }) ?? SQLValue.null,
        ]
    }
}

// the quoted table name for the DataItem
let QTBL = "\"\(DataItem.tableName)\""

public class DataBakeManager : ObservableObject {
    var ctx: SQLContext

    /// A reusable statement for inserting new DataItem instance rows
    private var insertStatement: SQLStatement?

    /// A reusable statement for selecting a DataItem by the rowid
    private var selectByIDStatement: SQLStatement?

    /// This needs to be set when manually editing rows from the update hook so as to not trigger cyclic updates
    private var updateFromHook: Bool = false

    /// A list of all the rowids for all the `DataItem` instances in the database.
    ///
    /// This property is updated whenever a row is added or delete from the database, by use of the `onUpdate` hook.
    @Published public var rowids: [DataItem.RowID] = [] {
        willSet {
            handleRowIdChange(newValue: newValue)
        }
    }

    /// Creates a new database manager with the given persistent database path, or `nil`
    public init(url: URL?) throws {
        self.ctx = try SQLContext(path: url?.path ?? ":memory:", flags: [.readWrite, .create], logLevel: .info)

        try migrateSchema()
        try reload()
    }

    /// Creates the initial database schema and performs any migrations for the schema version integer stored in the `DB_SCHEMA_VERSION` table.
    private func migrateSchema() throws {
        let startTime = Date.now

        // track the version of the schema in the database, which can be used for schema migration
        try ctx.exec(sql: "CREATE TABLE IF NOT EXISTS DB_SCHEMA_VERSION (id INTEGER PRIMARY KEY, version INTEGER)")
        try ctx.exec(sql: "INSERT OR IGNORE INTO DB_SCHEMA_VERSION (id, version) VALUES (0, 0)")
        var currentVersion = try ctx.query(sql: "SELECT version FROM DB_SCHEMA_VERSION").first?.first?.integerValue ?? 0

        func migrateSchema(v version: Int64, ddl: String) throws {
            if currentVersion < version {
                let startTime = Date.now
                try ctx.exec(sql: ddl) // perform the DDL operation
                // then update the schema version
                try ctx.exec(sql: "UPDATE DB_SCHEMA_VERSION SET version = ?", parameters: [SQLValue.integer(version)])
                currentVersion = version
                logger.log("updated database schema to \(version) in \(startTime.durationToNow)")
            }
        }


        // the initial creation script for a new database
        try migrateSchema(v: 1, ddl: """
        CREATE TABLE IF NOT EXISTS \(QTBL) (\(DataItem.CodingKeys.id.rawValue) INTEGER PRIMARY KEY AUTOINCREMENT)
        """)

        // incrementally migrate up to the current schema version
        func addDataItemColumn(_ key: DataItem.CodingKeys) -> String {
            "ALTER TABLE \(QTBL) ADD COLUMN \(key.rawValue) \(key.ddl)"
        }

        try migrateSchema(v: 2, ddl: addDataItemColumn(.title))
        try migrateSchema(v: 3, ddl: addDataItemColumn(.created))
        try migrateSchema(v: 4, ddl: addDataItemColumn(.modified))
        try migrateSchema(v: 5, ddl: addDataItemColumn(.contents))
        try migrateSchema(v: 6, ddl: addDataItemColumn(.rating))
        try migrateSchema(v: 7, ddl: addDataItemColumn(.thumbnail))
        // future migrations to follow…

        logger.log("initialized database in \(startTime.durationToNow)")

        // install an update hook to always keep the local list of ids in sync with the database
        ctx.onUpdate(hook: databaseUpdated)
    }

    /// Invoked from the `onUpdate` hook whenever a ROWID table changes in the database
    private func databaseUpdated(action: SQLAction, rowid: Int64, dbname: String, tblname: String) {
        updateFromHook = true
        defer { updateFromHook = false }
        //logger.debug("databaseUpdated: \(action.description) \(dbname).\(tblname) \(rowid)")
        if tblname == DataItem.tableName {
            switch action {
            case .insert: self.rowids.append(rowid)
            case .delete: self.rowids.removeAll(where: { $0 == rowid })
            case .update: self.rowids = self.rowids
            }
        }
    }

    private func handleRowIdChange(newValue: [DataItem.RowID]) {
        //logger.debug("handleRowIdChange: \(self.rowids.count) -> \(newValue.count)")
        // this property is updated from the SwiftUI list, and so we need to detect when the user deletes a list item and issue the delete statement
        if !updateFromHook, self.rowids.count != newValue.count {
            let oldids = Set(self.rowids)
            let newids = Set(newValue)
            let deleteRows = oldids.subtracting(newids)
            if !deleteRows.isEmpty {
                attempt {
                    try delete(ids: Array(deleteRows))
                }
            }
        }
    }

    /// Attempts the given operation and log an error if it fails
    public func attempt(block: () throws -> ()) {
        do {
            try block()
        } catch {
            logger.warning("attempt failure: \(error)")
        }
    }

    /// Reload all the records from the underlying table
    public func reload(orderBy: String? = nil) throws {
        let newIds = try self.queryIDs(orderBy: orderBy ?? "ROWID DESC")
        self.rowids = newIds
    }

    /// Deletes the items with the given IDs.
    public func delete(ids: [Int64]) throws {
        return try ctx.exec(sql: "DELETE FROM \(QTBL) WHERE ID IN (\(ids.map(\.description).joined(separator: ",")))")
    }

    /// Updates the items in the database based on their corresponding IDs.
    public func update(items: [DataItem]) throws {
        let sql = "UPDATE \(QTBL) SET " + DataItem.columnUpdate + " WHERE id = ?"
        let stmnt = try ctx.prepare(sql: sql)
        for item in items {
            if let id = item.id {
                try stmnt.update(parameters: item.itemParameters + [SQLValue.integer(id)])
            }
        }
        try stmnt.close()
    }

    /// Prepares the given SQL statement, caching and re-using it into the given statement handle.
    func prepare(sql: String, into statement: inout SQLStatement?) throws -> SQLStatement {
        if let stmnt = statement {
            #if SKIP
            return stmnt! // https://github.com/skiptools/skip/issues/50
            #else
            return stmnt // already cached
            #endif
        } else {
            let stmnt = try ctx.prepare(sql: sql)
            statement = stmnt // save to the cache
            return stmnt
        }
    }

    /// Insert new instances of the item into the database.
    @discardableResult public func insert(items: [DataItem]) throws -> [DataItem.RowID] {
        return try ctx.transaction {
            var ids: [DataItem.RowID] = []
            for item in items {
                try prepare(sql: DataItem.insertSQL, into: &insertStatement)
                    .update(parameters: item.itemParameters)
                ids.append(ctx.lastInsertRowID)
            }
            return ids
        }
    }

    /// Returns the total number of rows for a table.
    public func queryDataItemCount() throws -> Int64? {
        try ctx.prepare(sql: "SELECT COUNT(*) FROM \(QTBL)").nextValues(close: true)?.first?.integerValue
    }

    /// Fetches the items with the corresponding IDs.
    ///
    /// Note that the order of the returned items is unrelated to the order of the `ids` parameter, nor is the returned array guaranteed to contains all the identifiers, since missing elements are not detected nor considered an error.
    public func fetch(ids: [Int64]) throws -> [DataItem] {
        if ids.isEmpty {
            return []
        } else {
            let sql = "\(DataItem.CodingKeys.id.rawValue) IN (" + ids.map({ _ in "?" }).joined(separator: ",") + ")"
            return try queryDataItems(where: sql, ids.map({ SQLValue.integer($0) }), cache: ids.count == 1)
        }
    }

    public func queryDataItems(where whereClause: String? = nil, _ values: [SQLValue] = [], cache: Bool = false) throws -> [DataItem] {
        var sql = "SELECT \(DataItem.columnNames) FROM \(QTBL)"
        if let whereClause = whereClause {
            sql += " WHERE " + whereClause
        }
        let stmnt = try cache == true
            ? prepare(sql: sql, into: &selectByIDStatement)
            : ctx.prepare(sql: sql)
        try stmnt.bind(parameters: values)
        defer {
            if cache {
                stmnt.reset()
            } else {
                try? stmnt.close()
            }
        }
        var items: [DataItem] = []
        while try stmnt.next() {
            items.append(try DataItem(fromCursor: stmnt))
        }

        return items
    }

    public func queryIDs(limit: Int64? = nil, where whereClause: String? = nil, _ values: [SQLValue] = [], orderBy: String? = nil) throws -> [Int64] {
        let startTime = Date.now
        var sql = "SELECT \(DataItem.CodingKeys.id.rawValue) FROM \(QTBL)"
        if let whereClause = whereClause {
            sql += " WHERE " + whereClause
        }
        if let orderBy = orderBy {
            sql += " ORDER BY " + orderBy
        }
        let stmnt = try ctx.prepare(sql: sql)
        try stmnt.bind(parameters: values)
        defer { try? stmnt.close() }
        var ids: [Int64] = []
        while try stmnt.next() {
            ids.append(stmnt.integer(at: 0))
        }

        // iOS Sim: 1000 rows in 0.001
        // Android emulator: 1000 rows in 0.005
        logger.log("fetched \(ids.count) in \(startTime.durationToNow)")
        return ids
    }
}

public struct MissingColumnError : LocalizedError {
    public var errorDescription: String?
}


extension Date {
    /// The duration of this Date from now, rounded to the millisecond
    public var durationToNow: Double {
        round(Date.now.timeIntervalSince(self) * 1_000.0) / 1_000.0
    }
}
