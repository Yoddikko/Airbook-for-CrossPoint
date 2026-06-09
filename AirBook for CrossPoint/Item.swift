import Foundation

struct Book: Identifiable, Codable {
    let id: UUID
    var filename: String
    var addedDate: Date
    var fileSize: Int64

    var displayTitle: String {
        var name = (filename as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "-", with: " ")
        return name
    }

    var ext: String {
        (filename as NSString).pathExtension.lowercased()
    }
}

enum BookImportError: LocalizedError {
    case unsupportedFormat
    case copyFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported format. Use EPUB, TXT, BMP, XTC or XTCH."
        case .copyFailed(let e):
            return "Import failed: \(e.localizedDescription)"
        }
    }
}

@Observable
class BookStore {
    var books: [Book] = []

    private let booksDir: URL
    private let metaURL: URL

    static let supportedExtensions = Set(["epub", "txt", "bmp", "xtc", "xtch"])

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDir = docs.appendingPathComponent("Books", isDirectory: true)
        metaURL = docs.appendingPathComponent("books_meta.json")
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
        loadMeta()
    }

    func importBook(from url: URL) throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        guard BookStore.supportedExtensions.contains(ext) else {
            throw BookImportError.unsupportedFormat
        }

        let originalName = url.lastPathComponent
        var destName = originalName
        var destURL = booksDir.appendingPathComponent(destName)
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            let base = (originalName as NSString).deletingPathExtension
            destName = "\(base) (\(counter)).\(ext)"
            destURL = booksDir.appendingPathComponent(destName)
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            throw BookImportError.copyFailed(error)
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let book = Book(id: UUID(), filename: destName, addedDate: Date(), fileSize: size)
        books.insert(book, at: 0)
        saveMeta()
        return book
    }

    func deleteBook(_ book: Book) {
        try? FileManager.default.removeItem(at: fileURL(for: book))
        books.removeAll { $0.id == book.id }
        saveMeta()
    }

    func fileURL(for book: Book) -> URL {
        booksDir.appendingPathComponent(book.filename)
    }

    func fileData(for book: Book) throws -> Data {
        try Data(contentsOf: fileURL(for: book))
    }

    private func loadMeta() {
        guard let data = try? Data(contentsOf: metaURL),
              let decoded = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = decoded.filter {
            FileManager.default.fileExists(atPath: fileURL(for: $0).path)
        }
    }

    private func saveMeta() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }
}
