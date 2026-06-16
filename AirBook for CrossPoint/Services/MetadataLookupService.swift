import Foundation

// MARK: - Query / candidate

struct MetadataQuery: Hashable {
    var title: String?
    var author: String?
    var isbn: String?

    var isEmpty: Bool {
        (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (isbn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var cacheKey: String {
        "\(title?.lowercased() ?? "")|\(author?.lowercased() ?? "")|\(isbn ?? "")"
    }
}

enum MetadataProviderID: String, Codable, Equatable {
    case googleBooks
    case openLibrary
    case iTunes
}

struct MetadataCandidate: Identifiable, Codable, Equatable {
    var id: String                  // provider-scoped
    var title: String
    var authors: [String]
    var publisher: String?
    var publishedYear: Int?
    var language: String?
    var isbn: String?
    var synopsis: String?
    var pageCount: Int?
    var coverURL: URL?
    var provider: MetadataProviderID

    /// Normalized title+author key for dedup across providers.
    var normalizedKey: String {
        let t = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let a = authors.joined(separator: " ").lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return "\(t)|\(a)"
    }

    /// Score for "data richness" — used to pick the best candidate when
    /// duplicates appear across providers.
    var fieldScore: Int {
        var n = 0
        if publisher != nil { n += 1 }
        if publishedYear != nil { n += 1 }
        if language != nil { n += 1 }
        if isbn != nil { n += 1 }
        if let s = synopsis, !s.isEmpty { n += 2 }
        if pageCount != nil { n += 1 }
        if coverURL != nil { n += 2 }
        return n
    }

    /// Merge missing fields from `other` into self. Self's existing non-nil
    /// values are preserved. Used to combine duplicates across providers.
    mutating func fillMissing(from other: MetadataCandidate) {
        if publisher == nil { publisher = other.publisher }
        if publishedYear == nil { publishedYear = other.publishedYear }
        if language == nil { language = other.language }
        if isbn == nil { isbn = other.isbn }
        if synopsis == nil || synopsis?.isEmpty == true { synopsis = other.synopsis }
        if pageCount == nil { pageCount = other.pageCount }
        if coverURL == nil { coverURL = other.coverURL }
        if authors.isEmpty { authors = other.authors }
    }
}

// MARK: - Provider protocol

protocol MetadataProvider: Sendable {
    var id: MetadataProviderID { get }
    func search(_ query: MetadataQuery) async throws -> [MetadataCandidate]
}

enum MetadataLookupError: Error {
    case emptyQuery
    case offline
    case invalidResponse
}

// MARK: - Google Books

struct GoogleBooksProvider: MetadataProvider {
    let id: MetadataProviderID = .googleBooks
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
        guard !query.isEmpty else { throw MetadataLookupError.emptyQuery }
        // Run two queries in parallel: a structured one (intitle:/inauthor:)
        // and a free-text one. Google's structured matcher is restrictive;
        // free-text catches results the structured form misses.
        async let structured = run(structuredQueryString(query))
        async let plain = run(plainQueryString(query))
        let a = (try? await structured) ?? []
        let b = (try? await plain) ?? []
        // Dedup by Google volume id, structured wins ordering.
        var seen = Set<String>()
        var merged: [MetadataCandidate] = []
        for c in a + b where seen.insert(c.id).inserted { merged.append(c) }
        return merged
    }

    private func structuredQueryString(_ q: MetadataQuery) -> String {
        var parts: [String] = []
        if let isbn = q.isbn, !isbn.isEmpty { parts.append("isbn:\(isbn)") }
        if let t = q.title, !t.isEmpty { parts.append("intitle:\(t)") }
        if let a = q.author, !a.isEmpty { parts.append("inauthor:\(a)") }
        return parts.joined(separator: "+")
    }

    private func plainQueryString(_ q: MetadataQuery) -> String {
        if let isbn = q.isbn, !isbn.isEmpty { return isbn }
        var parts: [String] = []
        if let t = q.title, !t.isEmpty { parts.append(t) }
        if let a = q.author, !a.isEmpty { parts.append(a) }
        return parts.joined(separator: " ")
    }

    private func run(_ q: String) async throws -> [MetadataCandidate] {
        guard !q.isEmpty else { return [] }
        var comps = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "printType", value: "books")
        ]
        guard let url = comps.url else { return [] }

        let (data, _) = try await session.data(from: url)
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String
                let volumeInfo: VolumeInfo?
            }
            struct VolumeInfo: Decodable {
                let title: String?
                let subtitle: String?
                let authors: [String]?
                let publisher: String?
                let publishedDate: String?
                let description: String?
                let industryIdentifiers: [Identifier]?
                let pageCount: Int?
                let language: String?
                let imageLinks: ImageLinks?
            }
            struct Identifier: Decodable {
                let type: String
                let identifier: String
            }
            struct ImageLinks: Decodable {
                let thumbnail: String?
                let smallThumbnail: String?
                let small: String?
                let medium: String?
                let large: String?
            }
            let items: [Item]?
        }

        let resp = try JSONDecoder().decode(Response.self, from: data)
        return (resp.items ?? []).compactMap { item -> MetadataCandidate? in
            guard let vi = item.volumeInfo, let title = vi.title else { return nil }
            let year = vi.publishedDate.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
            let isbn = vi.industryIdentifiers?.first(where: { $0.type.contains("ISBN_13") })?.identifier
                ?? vi.industryIdentifiers?.first(where: { $0.type.contains("ISBN_10") })?.identifier
            // Prefer larger images when available; upgrade http→https for ATS.
            let raw = vi.imageLinks?.large
                ?? vi.imageLinks?.medium
                ?? vi.imageLinks?.small
                ?? vi.imageLinks?.thumbnail
                ?? vi.imageLinks?.smallThumbnail
            let coverString = raw?.replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&edge=curl", with: "")
                .replacingOccurrences(of: "edge=curl", with: "")
            // Bump Google's `zoom` parameter for higher resolution.
            let coverURL = coverString.flatMap(upgradeGoogleCover)
            let combinedTitle = (vi.subtitle?.isEmpty == false)
                ? "\(title): \(vi.subtitle!)"
                : title
            return MetadataCandidate(
                id: "google:\(item.id)",
                title: combinedTitle,
                authors: vi.authors ?? [],
                publisher: vi.publisher,
                publishedYear: year,
                language: vi.language,
                isbn: isbn,
                synopsis: vi.description,
                pageCount: vi.pageCount,
                coverURL: coverURL,
                provider: .googleBooks)
        }
    }

    private func upgradeGoogleCover(_ raw: String) -> URL? {
        guard var comps = URLComponents(string: raw) else { return URL(string: raw) }
        var items = comps.queryItems ?? []
        if let i = items.firstIndex(where: { $0.name == "zoom" }) {
            items[i] = URLQueryItem(name: "zoom", value: "2")
        } else {
            items.append(URLQueryItem(name: "zoom", value: "2"))
        }
        comps.queryItems = items
        return comps.url
    }
}

// MARK: - Open Library

struct OpenLibraryProvider: MetadataProvider {
    let id: MetadataProviderID = .openLibrary
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
        guard !query.isEmpty else { throw MetadataLookupError.emptyQuery }
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        var items: [URLQueryItem] = []
        if let isbn = query.isbn, !isbn.isEmpty {
            items.append(URLQueryItem(name: "isbn", value: isbn))
        }
        if let t = query.title, !t.isEmpty {
            items.append(URLQueryItem(name: "title", value: t))
        }
        if let a = query.author, !a.isEmpty {
            items.append(URLQueryItem(name: "author", value: a))
        }
        items.append(URLQueryItem(name: "limit", value: "15"))
        comps.queryItems = items
        guard let url = comps.url else { throw MetadataLookupError.invalidResponse }

        let (data, _) = try await session.data(from: url)
        struct Response: Decodable {
            struct Doc: Decodable {
                let key: String?
                let title: String?
                let subtitle: String?
                let author_name: [String]?
                let publisher: [String]?
                let first_publish_year: Int?
                let isbn: [String]?
                let language: [String]?
                let cover_i: Int?
                let number_of_pages_median: Int?
            }
            let docs: [Doc]?
        }

        let resp = try JSONDecoder().decode(Response.self, from: data)
        var candidates = (resp.docs ?? []).compactMap { doc -> MetadataCandidate? in
            guard let title = doc.title else { return nil }
            // Larger cover (-L is ~640px tall) for nicer thumbnails.
            let coverByID = doc.cover_i.flatMap {
                URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg")
            }
            // Fallback to ISBN-based cover if the ID is missing.
            let coverByISBN = doc.isbn?.first.flatMap {
                URL(string: "https://covers.openlibrary.org/b/isbn/\($0)-L.jpg")
            }
            let stableID = doc.key ?? UUID().uuidString
            let combinedTitle = (doc.subtitle?.isEmpty == false)
                ? "\(title): \(doc.subtitle!)"
                : title
            return MetadataCandidate(
                id: "ol:\(stableID)",
                title: combinedTitle,
                authors: doc.author_name ?? [],
                publisher: doc.publisher?.first,
                publishedYear: doc.first_publish_year,
                language: doc.language?.first,
                isbn: doc.isbn?.first,
                synopsis: nil,
                pageCount: doc.number_of_pages_median,
                coverURL: coverByID ?? coverByISBN,
                provider: .openLibrary)
        }

        // Enrich the top results with descriptions from /works/{key}.json.
        // Limited to first 6 to keep it snappy.
        let enrichCount = min(6, candidates.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            for i in 0..<enrichCount {
                let key = candidates[i].id.replacingOccurrences(of: "ol:", with: "")
                guard key.hasPrefix("/works/") else { continue }
                group.addTask {
                    let detail = await Self.fetchWorkDescription(key: key, session: session)
                    return (i, detail)
                }
            }
            for await (i, desc) in group {
                if let desc, !desc.isEmpty {
                    candidates[i].synopsis = desc
                }
            }
        }
        return candidates
    }

    private static func fetchWorkDescription(key: String, session: URLSession) async -> String? {
        guard let url = URL(string: "https://openlibrary.org\(key).json") else { return nil }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        // `description` may be a string or { value: ... }.
        struct StringField: Decodable {
            let value: String
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = dict["description"] as? String { return s }
            if let d = dict["description"] as? [String: Any],
               let v = d["value"] as? String { return v }
        }
        return nil
    }
}

// MARK: - iTunes Books

struct iTunesBooksProvider: MetadataProvider {
    let id: MetadataProviderID = .iTunes
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
        guard !query.isEmpty else { throw MetadataLookupError.emptyQuery }
        let term = [query.isbn, query.title, query.author]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return [] }

        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "ebook"),
            URLQueryItem(name: "limit", value: "15")
        ]
        guard let url = comps.url else { return [] }

        let (data, _) = try await session.data(from: url)
        struct Response: Decodable {
            struct Item: Decodable {
                let trackId: Int?
                let trackName: String?
                let artistName: String?
                let description: String?
                let artworkUrl100: String?
                let artworkUrl60: String?
                let releaseDate: String?
                let genres: [String]?
            }
            let results: [Item]
        }

        let resp = try JSONDecoder().decode(Response.self, from: data)
        return resp.results.compactMap { item -> MetadataCandidate? in
            guard let title = item.trackName, let trackID = item.trackId else { return nil }
            let year = item.releaseDate.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
            // iTunes returns 100×100 — bump to 600×600 by swapping the suffix.
            let raw = item.artworkUrl100 ?? item.artworkUrl60
            let coverURL = raw
                .flatMap { $0.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg") }
                .flatMap { $0.replacingOccurrences(of: "100x100bb.png", with: "600x600bb.png") }
                .flatMap { $0.replacingOccurrences(of: "60x60bb.jpg", with: "600x600bb.jpg") }
                .flatMap(URL.init(string:))
            return MetadataCandidate(
                id: "itunes:\(trackID)",
                title: title,
                authors: item.artistName.map { [$0] } ?? [],
                publisher: nil,
                publishedYear: year,
                language: nil,
                isbn: nil,
                synopsis: item.description.flatMap(stripHTML),
                pageCount: nil,
                coverURL: coverURL,
                provider: .iTunes)
        }
    }

    private func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Lookup service

@Observable
@MainActor
final class MetadataLookupService {
    @ObservationIgnored private let providers: [any MetadataProvider]
    @ObservationIgnored private let cacheDir: URL
    @ObservationIgnored private let cacheTTL: TimeInterval = 60 * 60 * 24 * 30  // 30 days

    init(providers: [any MetadataProvider] = [
        GoogleBooksProvider(),
        OpenLibraryProvider(),
        iTunesBooksProvider()
    ]) {
        self.providers = providers
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDir = docs.appendingPathComponent("metadata_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func search(_ query: MetadataQuery) async throws -> [MetadataCandidate] {
        guard !query.isEmpty else { throw MetadataLookupError.emptyQuery }
        if let cached = readCache(query) { return cached }

        let results = await runProvidersInParallel(query)
        let merged = mergeAndRank(results, query: query)
        writeCache(query, candidates: merged)
        return merged
    }

    // MARK: - Internal

    private func runProvidersInParallel(_ query: MetadataQuery) async -> [[MetadataCandidate]] {
        await withTaskGroup(of: [MetadataCandidate].self) { group in
            for p in providers {
                group.addTask {
                    (try? await p.search(query)) ?? []
                }
            }
            var collected: [[MetadataCandidate]] = []
            for await chunk in group { collected.append(chunk) }
            return collected
        }
    }

    private func mergeAndRank(_ buckets: [[MetadataCandidate]],
                              query: MetadataQuery) -> [MetadataCandidate] {
        // Dedup by normalized title+author. For duplicates, keep the
        // candidate with the richest data and merge missing fields from
        // the others — so a Google entry that has a synopsis can still
        // borrow an OpenLibrary ISBN, and vice versa.
        var byKey: [String: MetadataCandidate] = [:]
        for bucket in buckets {
            for candidate in bucket {
                let key = candidate.normalizedKey
                if var existing = byKey[key] {
                    if candidate.fieldScore > existing.fieldScore {
                        // New candidate is richer — promote it, then fill
                        // from the old winner.
                        var promoted = candidate
                        promoted.fillMissing(from: existing)
                        byKey[key] = promoted
                    } else {
                        existing.fillMissing(from: candidate)
                        byKey[key] = existing
                    }
                } else {
                    byKey[key] = candidate
                }
            }
        }

        // ISBN-based cover fallback: any candidate that still lacks a
        // cover but has an ISBN gets a generated OpenLibrary URL.
        for key in byKey.keys {
            if byKey[key]?.coverURL == nil,
               let isbn = byKey[key]?.isbn, !isbn.isEmpty,
               let url = URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg") {
                byKey[key]?.coverURL = url
            }
        }

        let qTitle = (query.title ?? "").lowercased()
        return byKey.values.sorted {
            // ISBN exact match wins.
            if let qIsbn = query.isbn, !qIsbn.isEmpty {
                let aMatch = $0.isbn == qIsbn
                let bMatch = $1.isbn == qIsbn
                if aMatch != bMatch { return aMatch }
            }
            // Richer data wins next.
            if $0.fieldScore != $1.fieldScore { return $0.fieldScore > $1.fieldScore }
            // Closer title wins last.
            let aDelta = abs($0.title.count - qTitle.count)
            let bDelta = abs($1.title.count - qTitle.count)
            return aDelta < bDelta
        }
    }

    private func cacheURL(_ query: MetadataQuery) -> URL {
        let hash = sha256(query.cacheKey)
        return cacheDir.appendingPathComponent("\(hash).json")
    }

    private func readCache(_ query: MetadataQuery) -> [MetadataCandidate]? {
        let url = cacheURL(query)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mod) < cacheTTL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MetadataCandidate].self, from: data) else {
            return nil
        }
        return decoded
    }

    private func writeCache(_ query: MetadataQuery, candidates: [MetadataCandidate]) {
        guard let data = try? JSONEncoder().encode(candidates) else { return }
        try? data.write(to: cacheURL(query), options: .atomic)
    }

    private func sha256(_ s: String) -> String {
        // CryptoKit-free, fast enough for cache keys: FNV-1a 64-bit hex.
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
