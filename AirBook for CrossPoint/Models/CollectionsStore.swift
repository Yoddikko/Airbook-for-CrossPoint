import Foundation
import SwiftUI

// MARK: - Collection
//
// User-defined tag for grouping books. A book can live in multiple
// collections; the per-book ReadingState.collections array stores collection
// names (not IDs) so a book file can be opened on a fresh install and still
// resolve its tags.

struct Collection: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    /// Encoded as #RRGGBB hex; nil → use paperInk.
    var colorHex: String?
    /// Stable sort key inside the toolbar chip strip.
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, colorHex: String? = nil, sortIndex: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

// MARK: - Collections store

@Observable
@MainActor
final class CollectionsStore {
    private(set) var collections: [Collection] = []

    @ObservationIgnored private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("collections.json")
        load()
    }

    // MARK: - Queries

    func collection(named name: String) -> Collection? {
        collections.first { $0.name == name }
    }

    var sortedNames: [String] {
        collections.sorted { $0.sortIndex < $1.sortIndex }.map(\.name)
    }

    // MARK: - Mutations

    @discardableResult
    func add(name: String, colorHex: String? = nil) -> Collection {
        if let existing = collection(named: name) { return existing }
        let c = Collection(name: name, colorHex: colorHex,
                           sortIndex: (collections.map(\.sortIndex).max() ?? -1) + 1)
        collections.append(c)
        save()
        return c
    }

    func rename(_ collection: Collection, to newName: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }),
              !collections.contains(where: { $0.name == newName && $0.id != collection.id }) else {
            return
        }
        collections[idx].name = newName
        save()
        // Callers are responsible for rewriting affected ReadingState.collections;
        // expose the old/new pair via the return rather than walking sidecars
        // here, since this store has no reference to ReadingStateStore.
    }

    func setColor(_ hex: String?, for collection: Collection) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx].colorHex = hex
        save()
    }

    func remove(_ collection: Collection) {
        collections.removeAll { $0.id == collection.id }
        save()
    }

    func reorder(_ orderedIDs: [UUID]) {
        for (i, id) in orderedIDs.enumerated() {
            if let idx = collections.firstIndex(where: { $0.id == id }) {
                collections[idx].sortIndex = i
            }
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode([Collection].self, from: data) {
            collections = decoded.sorted { $0.sortIndex < $1.sortIndex }
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(collections) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
