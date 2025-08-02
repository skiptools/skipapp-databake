import Foundation
import OSLog
import Observation
import SkipSQL
import SkipSQLPlus // for full-text search, JSON, or encryption support

let logger: Logger = Logger(subsystem: "skip.data.bake.Model", category: "DataBake")

/// Sample data item stored in the database.
public struct DataItem : SQLCodable {
    public var id: Int64?
    static let id = SQLColumn(name: "id", type: .long, primaryKey: true, autoincrement: true)
    public var title: String
    static let title = SQLColumn(name: "title", type: .text, nullable: false)
    public var created: Date
    static let created = SQLColumn(name: "created", type: .real, nullable: false)
    public var modified: Date?
    static let modified = SQLColumn(name: "modified", type: .real, nullable: true)
    public var contents: String
    static let contents = SQLColumn(name: "contents", type: .text, nullable: false)

    public static var table = SQLTable(name: "DataItem", columns: [id, title, created, modified, contents])

    public init(id: Int64? = nil, title: String, created: Date? = nil, modified: Date? = nil, contents: String) {
        self.id = id
        self.title = title
        self.created = created ?? Date.now
        self.modified = modified
        self.contents = contents
    }

    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try Self.id.longValueRequired(in: row)
        self.title = try Self.title.textValueRequired(in: row)
        self.created = try Date(timeIntervalSince1970: Self.created.realValueRequired(in: row)) // non-nullable
        self.modified = Self.modified.realValue(in: row).flatMap { Date(timeIntervalSince1970: $0) } // nullable
        self.contents = try Self.contents.textValueRequired(in: row)
    }

    /// Updates the value of the given column with the given value
    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id)
        row[Self.title] = SQLValue(self.title)
        row[Self.created] = SQLValue(self.created.timeIntervalSince1970)
        row[Self.modified] = SQLValue(self.modified?.timeIntervalSince1970)
        row[Self.contents] = SQLValue(self.contents)
    }

    public var preview: DataItemPreview {
        return DataItemPreview(id: id ?? 0, title: title)
    }
}

/// Preview form of data item for displaying in lists, etc. without loading full objects into memory.
public struct DataItemPreview : SQLCodable, Identifiable {
    public var id: Int64
    static let id = DataItem.id
    public var title: String
    static let title = DataItem.title

    public static var table = SQLTable(name: DataItem.table.name, columns: [id, title])

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }

    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try Self.id.longValueRequired(in: row)
        self.title = try Self.title.textValueRequired(in: row)
    }

    /// Updates the value of the given column with the given value
    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id)
        row[Self.title] = SQLValue(self.title)
    }
}

/// Notification posted by the model when data changes.
extension Notification.Name {
    public static var dataItemsDidChange: Notification.Name {
        return Notification.Name("dataItemsDidChange")
    }
}

/// Payload of `dataItemsDidChange` notifications.
public struct DataItemsChange {
    public let inserts: [DataItem]
    public let updates: [Int64: (old: DataItem, new: DataItem)]
    /// Nil set means all records were deleted.
    public let deletes: Set<Int64>?

    public init(inserts: [DataItem] = [], updates: [(DataItem, DataItem)] = [], deletes: [Int64]? = []) {
        self.inserts = inserts
        self.updates = updates.reduce(into: [Int64: (DataItem, DataItem)]()) { updates, current in
            if let id = current.0.id {
                updates[id] = current
            }
        }
        self.deletes = deletes == nil ? nil : Set(deletes!)
    }
}

/// Provides serialized, strongly-typed access to data items.
public final class DataBakeModel {
    public let ctx: SQLContext
    private var schemaInitializationResult: Result<Void, Error>?

    public init(url: URL?) throws {
        ctx = try SQLContext(path: url?.path ?? ":memory:", flags: [.readWrite, .create], configuration: .plus)
        ctx.trace { sql in
            logger.info("SQL: \(sql)")
        }
    }

    /// Return previews of all items, optionally filtering on the title.
    ///
    /// Returned items are sorted on ID.
    public func dataItemPreviews(titlePrefix: String = "", descending: Bool = false) throws -> [DataItemPreview] {
        try initializeSchema()
        return try ctx.query(DataItemPreview.self, where: titlePrefix.isEmpty ? nil : .like(DataItem.title, SQLValue.text(titlePrefix + "%")), orderBy: [(DataItemPreview.id, descending ? .descending : .ascending)]).load()
    }

    /// Return the data item with the given ID.
    public func dataItem(id: Int64) throws -> DataItem? {
        try initializeSchema()
        return try ctx.fetch(DataItem.self, id: SQLValue(id))
    }

    /// Insert the given data items.
    ///
    /// - Returns The inserted items with their auto-assigned IDs populated.
    @discardableResult public func insert(_ dataItems: [DataItem]) throws -> [DataItem] {
        try initializeSchema()
        var insertedItems: [DataItem] = []
        try ctx.transaction {
            for dataItem in dataItems {
                try insertedItems.append(ctx.insert(dataItem))
            }
        }
        NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(inserts: insertedItems))
        return insertedItems
    }

    /// Update the given item.
    ///
    /// - Returns: Whether the record was found.
    @discardableResult public func update(_ dataItem: DataItem) throws -> Bool {
        try initializeSchema()
        guard let id = dataItem.id,
              let existingItem = try self.dataItem(id: id) else {
            return false
        }

        try ctx.update(dataItem)
        if ctx.changes > 0 {
            NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(updates: [(existingItem, dataItem)]))
            return true
        } else {
            return false
        }
    }

    /// Delete the data items with the given IDs, or all items if no array is given.
    ///
    /// - Returns: The number of records deleted.
    @discardableResult public func deleteDataItems(items: [DataItemPreview]? = nil) throws -> Int {
        try initializeSchema()
        if let items {
            try ctx.delete(instances: items)
            NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(deletes: items.map(\.id)))
        } else {
            try ctx.delete(DataItem.self)
            NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(deletes: nil))
        }
        return Int(ctx.changes)
    }

    private func initializeSchema() throws {
        switch schemaInitializationResult {
        case .success:
            return
        case .failure(let failure):
            throw failure
        case nil:
            break
        }

        do {
            var version = try currentSchemaVersion()
            version = try migrateSchema(v: Int64(1), current: version, ddl: DataItem.table.createTableSQL(withIndexes: false))
            version = try migrateSchema(v: Int64(2), current: version, ddl: DataItem.table.createIndexSQL())
            // Future column additions, etc here...
            schemaInitializationResult = .success(())
        } catch {
            schemaInitializationResult = .failure(error)
            throw error
        }
    }

    private func currentSchemaVersion() throws -> Int64 {
        try ctx.exec(sql: "CREATE TABLE IF NOT EXISTS SchemaVersion (id INTEGER PRIMARY KEY, version INTEGER)")
        try ctx.exec(sql: "INSERT OR IGNORE INTO SchemaVersion (id, version) VALUES (0, 0)")
        return try ctx.selectAll(sql: "SELECT version FROM SchemaVersion").first?.first?.longValue ?? Int64(0)
    }

    private func migrateSchema(v version: Int64, current: Int64, ddl: [SQLExpression]) throws -> Int64 {
        guard current < version else {
            return current
        }
        let startTime = Date.now
        try ctx.transaction {
            for ddlExpression in ddl {
                try ctx.exec(ddlExpression)
            }
            try ctx.exec(sql: "UPDATE SchemaVersion SET version = ?", parameters: [.long(version)])
        }
        logger.log("updated database schema to \(version) in \(Date.now.timeIntervalSince1970 - startTime.timeIntervalSince1970)")
        return version
    }
}
