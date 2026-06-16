import Compression
import Foundation

// MARK: - EPUB Metadata Extractor
//
// Parses an EPUB (a ZIP of XHTML + metadata + cover) and pulls title,
// author, publisher, publish year, language, ISBN, synopsis, and a cover
// image. Works offline, no external deps — a minimal ZIP reader (EOCD +
// central directory + local headers + raw-deflate decompress via the
// Compression framework) lives in this file, then `XMLParser` walks the
// container/OPF.
//
// Robustness: every recoverable failure path returns nil (so import keeps
// working — the user can still fall back to online lookup or manual edit)
// rather than throwing. Hard caps on read sizes keep a malicious EPUB from
// driving the app OOM during import.

struct EpubMetadataExtractor {

    struct ExtractedMetadata {
        var title: String?
        var author: String?
        var publisher: String?
        var publishedYear: Int?
        var language: String?
        var isbn: String?
        var synopsis: String?
        /// Raw cover image bytes (JPEG/PNG). Caller resizes + persists via
        /// BookStore.saveCoverData.
        var coverData: Data?
    }

    func extract(from fileURL: URL) async -> ExtractedMetadata? {
        guard fileURL.pathExtension.lowercased() == "epub" else { return nil }
        guard let zipData = try? Data(contentsOf: fileURL) else { return nil }
        // Hard cap: a sane EPUB rarely exceeds 100MB. Bigger files just skip
        // extraction so import doesn't stall.
        guard zipData.count < 100 * 1024 * 1024 else { return nil }

        guard let zip = MinimalZipReader(data: zipData) else { return nil }

        guard let containerData = zip.data(for: "META-INF/container.xml"),
              containerData.count < 8 * 1024 else { return nil }
        let container = EpubContainerParser()
        container.parse(containerData)
        guard let opfPath = container.opfPath else { return nil }

        guard let opfData = zip.data(for: opfPath),
              opfData.count < 256 * 1024 else { return nil }
        let opf = EpubOPFParser()
        opf.parse(opfData)

        var result = ExtractedMetadata()
        result.title = opf.title
        result.author = opf.author
        result.publisher = opf.publisher
        result.publishedYear = opf.publishedYear
        result.language = opf.language
        result.isbn = opf.isbn
        result.synopsis = opf.synopsis

        // Cover: prefer the explicit `<meta name="cover" content="<id>">`,
        // fall back to any manifest item with `properties="cover-image"`.
        let coverID = opf.coverItemID ?? opf.coverImageID
        if let id = coverID, let href = opf.manifestItems[id] {
            let opfDir = (opfPath as NSString).deletingLastPathComponent
            let coverPath = opfDir.isEmpty ? href : "\(opfDir)/\(href)"
            if let coverBytes = zip.data(for: coverPath),
               coverBytes.count < 4 * 1024 * 1024 {
                result.coverData = coverBytes
            }
        }

        return result
    }
}

// MARK: - Minimal ZIP reader
//
// Just enough ZIP to find named entries in an EPUB:
//   1. Scan from the end for the End-of-Central-Directory record (EOCD).
//   2. Read the central directory it points to.
//   3. Build a filename → entry table.
//   4. On read, jump to the local file header and decompress stored (0)
//      or deflate (8) streams.
// No ZIP64, no encryption, no spanning. EPUBs in the wild don't use those.

struct MinimalZipReader {
    private let data: Data
    private var entries: [String: Entry] = [:]

    private struct Entry {
        var compressionMethod: UInt16
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var localHeaderOffset: UInt32
    }

    init?(data: Data) {
        self.data = data
        if !buildIndex() { return nil }
    }

    func data(for filename: String) -> Data? {
        guard let entry = entries[filename] else { return nil }
        let lhOffset = Int(entry.localHeaderOffset)
        guard lhOffset + 30 <= data.count,
              readUInt32(at: lhOffset) == 0x04034B50 else { return nil }
        let filenameLen = Int(readUInt16(at: lhOffset + 26))
        let extraLen = Int(readUInt16(at: lhOffset + 28))
        let dataStart = lhOffset + 30 + filenameLen + extraLen
        let compressedSize = Int(entry.compressedSize)
        guard dataStart >= 0,
              dataStart + compressedSize <= data.count else { return nil }
        let compressed = data.subdata(in: dataStart..<(dataStart + compressedSize))

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            return nil
        }
    }

    // MARK: ZIP internals

    private mutating func buildIndex() -> Bool {
        guard data.count >= 22 else { return false }

        // 1. Find EOCD: scan backwards up to 64KB + 22 from end for
        //    signature 0x06054B50.
        let searchStart = max(0, data.count - 65536 - 22)
        var eocdOffset: Int? = nil
        var i = data.count - 22
        while i >= searchStart {
            if data[i] == 0x50, data[i + 1] == 0x4B,
               data[i + 2] == 0x05, data[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocdOff = eocdOffset, eocdOff + 22 <= data.count else { return false }

        let totalEntries = Int(readUInt16(at: eocdOff + 10))
        let cdSize = Int(readUInt32(at: eocdOff + 12))
        let cdOffset = Int(readUInt32(at: eocdOff + 16))
        guard cdOffset >= 0, cdOffset + cdSize <= data.count else { return false }

        // 2. Walk central directory.
        var offset = cdOffset
        for _ in 0..<totalEntries {
            guard offset + 46 <= data.count,
                  readUInt32(at: offset) == 0x02014B50 else { return false }
            let compressionMethod = readUInt16(at: offset + 10)
            let compressedSize = readUInt32(at: offset + 20)
            let uncompressedSize = readUInt32(at: offset + 24)
            let filenameLen = Int(readUInt16(at: offset + 28))
            let extraLen = Int(readUInt16(at: offset + 30))
            let commentLen = Int(readUInt16(at: offset + 32))
            let localHeaderOffset = readUInt32(at: offset + 42)

            guard offset + 46 + filenameLen <= data.count else { return false }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + filenameLen))
            if let name = String(data: nameData, encoding: .utf8) {
                entries[name] = Entry(
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset)
            }
            offset += 46 + filenameLen + extraLen + commentLen
        }
        return true
    }

    private func inflate(_ src: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0, expectedSize < 32 * 1024 * 1024 else { return nil }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { dstRaw -> Int in
            guard let dstPtr = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return src.withUnsafeBytes { srcRaw -> Int in
                guard let srcPtr = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dstPtr, expectedSize,
                                                 srcPtr, src.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written <= expectedSize else { return nil }
        return dst.prefix(written)
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }
}

// MARK: - container.xml parser

private final class EpubContainerParser: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName.hasSuffix("rootfile") || elementName == "rootfile" {
            if opfPath == nil, let path = attributeDict["full-path"] {
                opfPath = path
            }
        }
    }
}

// MARK: - OPF parser

private final class EpubOPFParser: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var publisher: String?
    var publishedYear: Int?
    var language: String?
    var isbn: String?
    var synopsis: String?
    /// Legacy `<meta name="cover" content="<id>">` (EPUB 2) cover hint.
    var coverItemID: String?
    /// Modern `<item properties="cover-image">` (EPUB 3) cover hint.
    var coverImageID: String?
    var manifestItems: [String: String] = [:]

    private var inMetadata = false
    private var inManifest = false
    private var currentValue = ""
    private var currentName = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentName = elementName
        currentValue = ""

        if elementName == "metadata" || elementName.hasSuffix(":metadata") {
            inMetadata = true
        } else if elementName == "manifest" || elementName.hasSuffix(":manifest") {
            inMetadata = false
            inManifest = true
        } else if elementName == "spine" || elementName.hasSuffix(":spine") {
            inManifest = false
        }

        if inManifest && (elementName == "item" || elementName.hasSuffix(":item")) {
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestItems[id] = href
            }
            if attributeDict["properties"]?.contains("cover-image") == true {
                if let id = attributeDict["id"] { coverImageID = id }
            }
        }

        if elementName == "meta" || elementName.hasSuffix(":meta") {
            if attributeDict["name"]?.lowercased() == "cover",
               let content = attributeDict["content"] {
                coverItemID = content
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { currentName = ""; currentValue = "" }
        guard inMetadata else { return }

        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let base = (elementName.contains(":")
            ? String(elementName.split(separator: ":").last ?? Substring(elementName))
            : elementName).lowercased()

        switch base {
        case "title":
            if title == nil { title = trimmed }
        case "creator":
            if author == nil { author = trimmed }
        case "publisher":
            if publisher == nil { publisher = trimmed }
        case "date":
            if publishedYear == nil {
                publishedYear = Int(trimmed.prefix(4))
            }
        case "language":
            if language == nil { language = trimmed }
        case "identifier":
            if isbn == nil {
                let cleaned = trimmed
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "isbn:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "urn:isbn:", with: "", options: .caseInsensitive)
                if cleaned.count == 10 || cleaned.count == 13,
                   cleaned.allSatisfy({ $0.isNumber || $0 == "X" }) {
                    isbn = cleaned
                }
            }
        case "description":
            if synopsis == nil { synopsis = trimmed }
        default:
            break
        }
    }
}
