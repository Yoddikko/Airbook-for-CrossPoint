import Foundation

// MARK: - Highlight color

enum HighlightColor: UInt8, Codable, Equatable, CaseIterable {
    case yellow = 1
    case blue = 2
    case pink = 3
    case green = 4
}

// MARK: - Dirty flags
//
// Per-book "needs sync" markers. Set when iOS mutates progress/bookmarks/
// highlights locally, cleared after a successful push to the device.

struct DirtyFlags: OptionSet, Codable, Equatable {
    let rawValue: UInt8

    static let progress   = DirtyFlags(rawValue: 1 << 0)
    static let bookmarks  = DirtyFlags(rawValue: 1 << 1)
    static let highlights = DirtyFlags(rawValue: 1 << 2)

    init(rawValue: UInt8) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.rawValue = try c.decode(UInt8.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Progress mark

struct ProgressMark: Codable, Equatable {
    var spineIndex: UInt16
    var pageNumber: UInt16
    var pageCount: UInt16
    /// 0…1.
    var percentage: Float
    /// Used for newest-wins merge with the device.
    var updatedAt: Date
}

// MARK: - Bookmark record

struct BookmarkRecord: Codable, Equatable, Identifiable {
    /// Stable across iOS↔device merges. Lazily generated for legacy device
    /// bookmarks (hash of xpath + creation order).
    let id: UUID
    var xpath: String
    /// First words of the page, capped at 200 chars.
    var summary: String
    var percentage: Float
    var spineIndex: UInt16
    var chapterPageCount: UInt16
    var chapterProgress: UInt16
    var createdAt: Date
    var updatedAt: Date
    /// Informational: tracks where this bookmark first appeared.
    var deviceOriginated: Bool
}

// MARK: - Highlight record
//
// xpath addresses the source XHTML, not rendered layout, so highlights stay
// stable when the device rebuilds its section cache. `snippet` is the iOS-
// only cached text — the device resolves the highlighted run at render time
// from its EPUB cache and never stores the body.

struct HighlightRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var xpathStart: String
    var offsetStart: UInt32
    var xpathEnd: String
    var offsetEnd: UInt32
    var colorTag: HighlightColor
    /// ≤480 chars on iOS, truncated to ≤120 when pushed to the device.
    var note: String?
    /// Local-only cached text of the highlighted run. Not pushed.
    var snippet: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Reading state (per-book sidecar payload)
//
// Persisted at Documents/BookState/<book uuid>.json. Loaded lazily on first
// access and cached in ReadingStateStore. Kept separate from books_meta.json
// so a corrupted highlight file can't take down the whole library.

struct ReadingState: Codable, Equatable {
    var version: Int
    var bookID: UUID
    var progress: ProgressMark?
    var bookmarks: [BookmarkRecord]
    var highlights: [HighlightRecord]
    /// Collection tag names; the master CollectionsStore owns the canonical
    /// list. Renaming a collection rewrites all sidecars.
    var collections: [String]
    var lastSyncedAt: Date?
    /// Decoded as a raw UInt8 so a malformed bitfield can't break the file;
    /// view via `dirtyFlags` for typed access.
    var dirtyFlagsRaw: UInt8

    var dirtyFlags: DirtyFlags {
        get { DirtyFlags(rawValue: dirtyFlagsRaw) }
        set { dirtyFlagsRaw = newValue.rawValue }
    }

    init(bookID: UUID,
         progress: ProgressMark? = nil,
         bookmarks: [BookmarkRecord] = [],
         highlights: [HighlightRecord] = [],
         collections: [String] = [],
         lastSyncedAt: Date? = nil,
         dirtyFlags: DirtyFlags = []) {
        self.version = 1
        self.bookID = bookID
        self.progress = progress
        self.bookmarks = bookmarks
        self.highlights = highlights
        self.collections = collections
        self.lastSyncedAt = lastSyncedAt
        self.dirtyFlagsRaw = dirtyFlags.rawValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.bookID = try c.decode(UUID.self, forKey: .bookID)
        self.progress = try c.decodeIfPresent(ProgressMark.self, forKey: .progress)
        self.bookmarks = try c.decodeIfPresent([BookmarkRecord].self, forKey: .bookmarks) ?? []
        self.highlights = try c.decodeIfPresent([HighlightRecord].self, forKey: .highlights) ?? []
        self.collections = try c.decodeIfPresent([String].self, forKey: .collections) ?? []
        self.lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        self.dirtyFlagsRaw = try c.decodeIfPresent(UInt8.self, forKey: .dirtyFlagsRaw) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case version, bookID, progress, bookmarks, highlights
        case collections, lastSyncedAt, dirtyFlagsRaw
    }
}
