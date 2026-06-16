import Foundation

// MARK: - Metadata Source

enum MetadataSource: String, Codable, Equatable {
    case filename
    case epubOpf
    case googleBooks
    case openLibrary
    case iTunes
    case manual
}

// MARK: - Book Metadata
//
// Library-level book info: title, author, cover, etc. Lives inside Book and
// is persisted in books_meta.json. Reading-state (progress, bookmarks,
// highlights, collection tags) is kept in per-book sidecar files instead —
// see ReadingState.

struct BookMetadata: Codable, Equatable {
    var title: String?
    var author: String?
    var publisher: String?
    var publishedYear: Int?
    var language: String?
    var isbn: String?
    var synopsis: String?
    var pageCountEstimate: Int?
    /// File at Documents/Covers/<uuid>.jpg. nil → procedural cover.
    var coverAssetID: UUID?
    var source: MetadataSource
    var fetchedAt: Date?

    init(title: String? = nil,
         author: String? = nil,
         publisher: String? = nil,
         publishedYear: Int? = nil,
         language: String? = nil,
         isbn: String? = nil,
         synopsis: String? = nil,
         pageCountEstimate: Int? = nil,
         coverAssetID: UUID? = nil,
         source: MetadataSource,
         fetchedAt: Date? = nil) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.publishedYear = publishedYear
        self.language = language
        self.isbn = isbn
        self.synopsis = synopsis
        self.pageCountEstimate = pageCountEstimate
        self.coverAssetID = coverAssetID
        self.source = source
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        self.publishedYear = try c.decodeIfPresent(Int.self, forKey: .publishedYear)
        self.language = try c.decodeIfPresent(String.self, forKey: .language)
        self.isbn = try c.decodeIfPresent(String.self, forKey: .isbn)
        self.synopsis = try c.decodeIfPresent(String.self, forKey: .synopsis)
        self.pageCountEstimate = try c.decodeIfPresent(Int.self, forKey: .pageCountEstimate)
        self.coverAssetID = try c.decodeIfPresent(UUID.self, forKey: .coverAssetID)
        self.source = try c.decodeIfPresent(MetadataSource.self, forKey: .source) ?? .filename
        self.fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case title, author, publisher, publishedYear, language, isbn
        case synopsis, pageCountEstimate, coverAssetID, source, fetchedAt
    }
}
