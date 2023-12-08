// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import Foundation
import OSLog
import Observation
import SkipSQL

let logger: Logger = Logger(subsystem: "skip.data.bake.Model", category: "DataBake")

/// Sample data item stored in the database.
public struct DataItem : Identifiable {
    public var id: Int64
    public var title: String
    public var created: Date
    public var modified: Date?
    public var contents: String

    public init(id: Int64 = 0, title: String, created: Date? = nil, modified: Date? = nil, contents: String) {
        self.id = id
        self.title = title
        self.created = created ?? Date.now
        self.modified = modified
        self.contents = contents
    }

    public var preview: DataItemPreview {
        return DataItemPreview(id: id, title: title)
    }
}

/// Preview form of data item for displaying in lists, etc. without loading full objects into memory.
public struct DataItemPreview : Identifiable {
    public var id: Int64
    public var title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
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
            updates[current.0.id] = current
        }
        self.deletes = deletes == nil ? nil : Set(deletes!)
    }
}

/// Provides serialized, strongly-typed access to data items.
public actor DataBakeModel {
    private let ctx: SQLContext
    private var schemaInitializationResult: Result<Void, Error>?

    public init(url: URL?) throws {
        ctx = try SQLContext(path: url?.path ?? ":memory:", flags: [.readWrite, .create], logLevel: .info)
    }

    /// Return previews of all items, optionally filtering on the title.
    ///
    /// Returned items are sorted on ID.
    public func dataItemPreviews(titlePrefix: String = "") throws -> [DataItemPreview] {
        try initializeSchema()
        let statement: SQLStatement
        if titlePrefix.isEmpty {
            statement = try ctx.prepare(sql: "SELECT id, title FROM DataItem ORDER BY id ASC")
        } else {
            statement = try ctx.prepare(sql: "SELECT id, title FROM DataItem WHERE title LIKE ? ORDER BY id ASC")
            try statement.bind(.text(titlePrefix + "%"), at: 1)
        }
        defer { do { try statement.close() } catch {} }

        var previews: [DataItemPreview] = []
        while try statement.next() {
            let id = statement.integer(at: 0)
            let title = statement.string(at: 1) ?? ""
            previews.append(DataItemPreview(id: id, title: title))
        }
        return previews
    }

    /// Return the data item with the given ID.
    public func dataItem(id: Int64) throws -> DataItem? {
        try initializeSchema()
        let statement = try ctx.prepare(sql: "SELECT id, title, created, modified, contents FROM DataItem WHERE id = ?")
        try statement.bind(.integer(id), at: 1)
        defer { do { try statement.close() } catch {} }

        guard try statement.next() else {
            return nil
        }
        let id = statement.integer(at: 0)
        let title = statement.string(at: 1) ?? ""
        let createdTime = statement.double(at: 2)
        let modifiedTime = statement.double(at: 3)
        let contents = statement.string(at: 4) ?? ""
        return DataItem(id: id, title: title, created: Date(timeIntervalSince1970: createdTime), modified: modifiedTime == 0.0 ? nil : Date(timeIntervalSince1970: modifiedTime), contents: contents)
    }

    /// Insert the given data items.
    ///
    /// - Returns The inserted items with their auto-assigned IDs populated.
    @discardableResult public func insert(_ dataItems: [DataItem]) throws -> [DataItem] {
        try initializeSchema()
        let statement = try ctx.prepare(sql: "INSERT INTO DataItem (title, created, modified, contents) VALUES (?, ?, ?, ?)")
        defer { do { try statement.close() } catch {} }

        var insertedItems: [DataItem] = []
        try ctx.transaction {
            for dataItem in dataItems {
                statement.reset()
                let values = Self.bindingValues(for: dataItem)
                try statement.update(parameters: values)

                var insertedItem = dataItem
                insertedItem.id = ctx.lastInsertRowID
                insertedItems.append(insertedItem)
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
        guard let existingItem = try self.dataItem(id: dataItem.id) else {
            return false
        }

        let statement = try ctx.prepare(sql: "UPDATE DataItem SET title = ?, created = ?, modified = ?, contents = ? WHERE id = ?")
        defer { do { try statement.close() } catch {} }

        var bindingValues = Self.bindingValues(for: dataItem)
        bindingValues.append(.integer(dataItem.id))
        try statement.update(parameters: bindingValues)
        if ctx.changes > 0 {
            NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(updates: [(existingItem, dataItem)]))
            return true
        } else {
            return false
        }
    }

    private static func bindingValues(for dataItem: DataItem) -> [SQLValue] {
        let modifiedValue: SQLValue = dataItem.modified == nil ? .null : .float(dataItem.modified!.timeIntervalSince1970)
        return [
            .text(dataItem.title),
            .float(dataItem.created.timeIntervalSince1970),
            modifiedValue,
            .text(dataItem.contents)
        ]
    }

    /// Delete the data items with the given IDs, or all items if no array is given.
    ///
    /// - Returns: The number of records deleted.
    @discardableResult public func deleteDataItems(ids: [Int64]? = nil) throws -> Int {
        try  initializeSchema()
        if let ids {
            try ctx.exec(sql: "DELETE FROM DataItem WHERE id IN (\(ids.map(\.description).joined(separator: ",")))")
            NotificationCenter.default.post(name: .dataItemsDidChange, object: DataItemsChange(deletes: ids))
        } else {
            try ctx.exec(sql: "DELETE FROM DataItem")
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
            var currentVersion = try currentSchemaVersion()
            currentVersion = try migrateSchema(v: Int64(1), current: currentVersion, ddl: """
            CREATE TABLE DataItem (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created FLOAT NOT NULL, modified FLOAT, contents TEXT NOT NULL)
            """)
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
        return try ctx.query(sql: "SELECT version FROM SchemaVersion").first?.first?.integerValue ?? Int64(0)
    }

    private func migrateSchema(v version: Int64, current: Int64, ddl: String) throws -> Int64 {
        guard current < version else {
            return current
        }
        let startTime = Date.now
        try ctx.transaction {
            try ctx.exec(sql: ddl)
            try ctx.exec(sql: "UPDATE SchemaVersion SET version = ?", parameters: [.integer(version)])
        }
        logger.log("updated database schema to \(version) in \(Date.now.timeIntervalSince1970 - startTime.timeIntervalSince1970)")
        return version
    }
}
