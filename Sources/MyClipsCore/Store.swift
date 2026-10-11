import Foundation

/// Clip history and pinboards in one SQLite file, searched with an FTS5 trigram index.
///
/// Item ids double as recency: reusing a clip moves it to a new highest id, so search can
/// walk the FTS index newest-first and stop at the limit instead of sorting every match.
public actor Store {
    private let db: Database

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try Database(path: url.path)
        try Self.migrate(db)
    }

    private static func migrate(_ db: Database) throws {
        let version = try db.query("PRAGMA user_version") { $0.int(0) }.first ?? 0
        if version < 1 { try createV1(db) }
        if version < 2 {
            try db.transaction {
                try db.execute("""
                    ALTER TABLE items ADD COLUMN pinned_at REAL;
                    CREATE INDEX items_pinned ON items(pinned_at) WHERE pinned_at IS NOT NULL;
                    PRAGMA user_version = 2;
                    """)
            }
        }
        if version < 3 {
            // Captures before CaptureRules treated file + embedded image data as an image.
            try db.transaction {
                try db.execute("""
                    UPDATE items SET kind = 'image' WHERE kind = 'file' AND id IN (
                        SELECT item_id FROM reps WHERE type IN ('public.png', 'public.jpeg', 'public.heic')
                    );
                    PRAGMA user_version = 3;
                    """)
            }
        }
    }

    static func createV1(_ db: Database) throws {
        try db.transaction {
            try db.execute("""
                CREATE TABLE items (
                    id INTEGER PRIMARY KEY,
                    hash TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    text TEXT NOT NULL,
                    source_bundle TEXT,
                    source_name TEXT,
                    created_at REAL NOT NULL,
                    used_at REAL NOT NULL,
                    byte_size INTEGER NOT NULL
                );
                CREATE TABLE reps (
                    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE ON UPDATE CASCADE,
                    item INTEGER NOT NULL,
                    type TEXT NOT NULL,
                    data BLOB NOT NULL,
                    PRIMARY KEY (item_id, item, type)
                ) WITHOUT ROWID;
                CREATE VIRTUAL TABLE items_fts USING fts5(
                    text, content = 'items', content_rowid = 'id',
                    tokenize = 'trigram remove_diacritics 1'
                );
                CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
                END;
                CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
                END;
                CREATE TRIGGER items_au AFTER UPDATE OF id ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
                    INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
                END;
                CREATE TABLE pinboards (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at REAL NOT NULL
                );
                CREATE TABLE pinboard_items (
                    pinboard_id INTEGER NOT NULL REFERENCES pinboards(id) ON DELETE CASCADE,
                    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE ON UPDATE CASCADE,
                    added_at REAL NOT NULL,
                    PRIMARY KEY (pinboard_id, item_id)
                );
                CREATE INDEX pinboard_items_item ON pinboard_items(item_id);
                PRAGMA user_version = 1;
                """)
        }
    }

    // MARK: History

    /// Inserts a new clip, or moves an identical existing one to the top. Returns its (new) id.
    @discardableResult
    public func record(_ payload: ClipPayload, at date: Date = .now) throws -> Int64 {
        let hash = CaptureRules.contentHash(payload.representations)
        let now = date.timeIntervalSince1970
        return try db.transaction {
            if let id = try db.query("SELECT id FROM items WHERE hash = ?", [.text(hash)], { $0.int(0) }).first {
                try db.run(
                    "UPDATE items SET source_bundle = ?, source_name = ? WHERE id = ?",
                    [Self.optional(payload.sourceBundleID), Self.optional(payload.sourceName), .int(id)]
                )
                return try moveToTop(id, at: date)
            }
            try db.run(
                """
                INSERT INTO items (hash, kind, text, source_bundle, source_name, created_at, used_at, byte_size)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [.text(hash), .text(payload.kind.rawValue), .text(payload.text),
                 Self.optional(payload.sourceBundleID), Self.optional(payload.sourceName),
                 .double(now), .double(now), .int(Int64(payload.byteSize))]
            )
            let id = db.lastInsertRowID
            let insert = try db.prepare("INSERT OR IGNORE INTO reps (item_id, item, type, data) VALUES (?, ?, ?, ?)")
            for rep in payload.representations {
                try insert.run([.int(id), .int(Int64(rep.item)), .text(rep.type), .blob(rep.data)])
            }
            return id
        }
    }

    /// Clips matching `query`. History lists pinned clips first (most recently pinned first), then the rest
    /// newest first. With a pinboard, only its clips, most recently added first. `kind` limits to one type.
    public func clips(matching query: String = "", in pinboard: Int64? = nil, kind: ClipKind? = nil, limit: Int = 200) throws -> [Clip] {
        let plan = SearchPlan(query)
        if let pinboard {
            return try fetch(plan, pinboard: pinboard, kind: kind, pinned: nil, limit: limit)
        }
        let pinned = try fetch(plan, pinboard: nil, kind: kind, pinned: true, limit: limit)
        return try pinned + fetch(plan, pinboard: nil, kind: kind, pinned: false, limit: limit - pinned.count)
    }

    /// `pinned`: true for only pinned clips, false for only unpinned, nil for both.
    private func fetch(_ plan: SearchPlan, pinboard: Int64?, kind: ClipKind?, pinned: Bool?, limit: Int) throws -> [Clip] {
        guard limit > 0 else { return [] }
        var sql = """
            SELECT i.id, i.kind, substr(i.text, 1, 1000), i.source_bundle, i.source_name,
                   i.created_at, i.used_at, i.byte_size, i.pinned_at IS NOT NULL
            """
        var values: [SQLValue] = []
        // FTS first, so a history search streams matches by descending rowid.
        if plan.ftsMatch != nil {
            sql += " FROM items_fts f JOIN items i ON i.id = f.rowid"
        } else {
            sql += " FROM items i"
        }
        if let pinboard {
            sql += " JOIN pinboard_items p ON p.item_id = i.id AND p.pinboard_id = ?"
            values.append(.int(pinboard))
        }
        sql += " WHERE 1"
        if let match = plan.ftsMatch {
            sql += " AND items_fts MATCH ?"
            values.append(.text(match))
        }
        for pattern in plan.likePatterns {
            sql += " AND i.text LIKE ? ESCAPE '\\'"
            values.append(.text(pattern))
        }
        if let pinned {
            sql += pinned ? " AND i.pinned_at IS NOT NULL" : " AND i.pinned_at IS NULL"
        }
        if let kind {
            sql += " AND i.kind = ?"
            values.append(.text(kind.rawValue))
        }
        if pinboard != nil {
            sql += " ORDER BY p.added_at DESC"
        } else if pinned == true {
            sql += " ORDER BY i.pinned_at DESC"
        } else {
            sql += plan.ftsMatch == nil ? " ORDER BY i.id DESC" : " ORDER BY f.rowid DESC"
        }
        sql += " LIMIT ?"
        values.append(.int(Int64(limit)))
        return try db.query(sql, values, Self.clip)
    }

    public func representations(of id: Int64) throws -> [Representation] {
        try db.query("SELECT item, type, data FROM reps WHERE item_id = ? ORDER BY item", [.int(id)]) {
            Representation(item: Int($0.int(0)), type: $0.text(1) ?? "", data: $0.blob(2))
        }
    }

    /// Moves a clip to the top of history. Returns its new id.
    @discardableResult
    public func markUsed(_ id: Int64, at date: Date = .now) throws -> Int64 {
        try db.transaction { try moveToTop(id, at: date) }
    }

    /// Reps, pinboard entries and the FTS row follow via ON UPDATE CASCADE and the items_au trigger.
    private func moveToTop(_ id: Int64, at date: Date) throws -> Int64 {
        let top = try db.query("SELECT max(id) FROM items") { $0.int(0) }.first ?? 0
        let newID = id == top ? id : top + 1
        try db.run("UPDATE items SET id = ?, used_at = ? WHERE id = ?", [.int(newID), .double(date.timeIntervalSince1970), .int(id)])
        return newID
    }

    public func delete(_ ids: [Int64]) throws {
        try db.transaction {
            let delete = try db.prepare("DELETE FROM items WHERE id = ?")
            for id in ids { try delete.run([.int(id)]) }
        }
    }

    /// Pins clips to the top of history, or unpins them.
    public func setPinned(_ ids: [Int64], _ pinned: Bool) throws {
        try db.transaction {
            let update = try db.prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
            for id in ids {
                try update.run([pinned ? .double(Date.now.timeIntervalSince1970) : .null, .int(id)])
            }
        }
    }

    /// Deletes everything that is neither pinned nor on a pinboard.
    public func clearHistory() throws {
        try db.run("DELETE FROM items WHERE \(Self.expirable)")
    }

    /// Keeps the `keep` most recently used expirable clips. Pinned and pinboard clips never expire.
    public func prune(keep: Int) throws {
        try db.run(
            """
            DELETE FROM items WHERE id IN (
                SELECT id FROM items WHERE \(Self.expirable)
                ORDER BY id DESC LIMIT -1 OFFSET ?
            )
            """,
            [.int(Int64(keep))]
        )
    }

    public func count() throws -> Int {
        Int(try db.query("SELECT count(*) FROM items") { $0.int(0) }.first ?? 0)
    }

    // MARK: Pinboards

    public func pinboards() throws -> [Pinboard] {
        try db.query(
            """
            SELECT b.id, b.name, count(p.item_id) FROM pinboards b
            LEFT JOIN pinboard_items p ON p.pinboard_id = b.id
            GROUP BY b.id ORDER BY b.created_at
            """
        ) { Pinboard(id: $0.int(0), name: $0.text(1) ?? "", itemCount: Int($0.int(2))) }
    }

    @discardableResult
    public func createPinboard(named name: String) throws -> Int64 {
        try db.run("INSERT INTO pinboards (name, created_at) VALUES (?, ?)", [.text(name), .double(Date.now.timeIntervalSince1970)])
        return db.lastInsertRowID
    }

    public func deletePinboard(_ id: Int64) throws {
        try db.run("DELETE FROM pinboards WHERE id = ?", [.int(id)])
    }

    public func pin(_ item: Int64, to pinboard: Int64) throws {
        try db.run(
            "INSERT OR IGNORE INTO pinboard_items (pinboard_id, item_id, added_at) VALUES (?, ?, ?)",
            [.int(pinboard), .int(item), .double(Date.now.timeIntervalSince1970)]
        )
    }

    public func unpin(_ item: Int64, from pinboard: Int64) throws {
        try db.run("DELETE FROM pinboard_items WHERE pinboard_id = ? AND item_id = ?", [.int(pinboard), .int(item)])
    }

    // MARK: Helpers

    private static let expirable = "pinned_at IS NULL AND id NOT IN (SELECT item_id FROM pinboard_items)"

    private static func optional(_ value: String?) -> SQLValue {
        value.map(SQLValue.text) ?? .null
    }

    private static func clip(_ row: Statement) -> Clip {
        Clip(
            id: row.int(0),
            kind: ClipKind(rawValue: row.text(1) ?? "") ?? .text,
            preview: row.text(2) ?? "",
            sourceBundleID: row.text(3),
            sourceName: row.text(4),
            createdAt: Date(timeIntervalSince1970: row.double(5)),
            usedAt: Date(timeIntervalSince1970: row.double(6)),
            byteSize: Int(row.int(7)),
            isPinned: row.int(8) != 0
        )
    }
}

/// Splits a query into whitespace tokens that must all match.
/// Trigram FTS only indexes 3+ character sequences, so shorter tokens fall back to LIKE.
struct SearchPlan {
    var ftsMatch: String?
    var likePatterns: [String] = []

    init(_ query: String) {
        var phrases: [String] = []
        for token in query.split(whereSeparator: \.isWhitespace).map(String.init) {
            if token.unicodeScalars.count >= 3 {
                phrases.append("\"" + token.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            } else {
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                likePatterns.append("%" + escaped + "%")
            }
        }
        ftsMatch = phrases.isEmpty ? nil : phrases.joined(separator: " ")
    }
}
