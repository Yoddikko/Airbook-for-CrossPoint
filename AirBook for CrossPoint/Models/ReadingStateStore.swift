import Foundation

// MARK: - Reading state store
//
// LRU-cached loader/writer for Documents/BookState/<uuid>.json sidecars. The
// underlying truth is the on-disk file; the in-memory cache caps at 32 books
// so a huge library doesn't bloat RAM. Mutations save atomically and bump
// `revision` so SwiftUI views can observe changes.

@Observable
@MainActor
final class ReadingStateStore {
    /// View-side observation token. Bumped on every mutation so SwiftUI can
    /// trigger re-renders without exposing the internal cache shape.
    private(set) var revision: Int = 0

    @ObservationIgnored private var cache: [UUID: ReadingState] = [:]
    @ObservationIgnored private var accessOrder: [UUID] = []
    @ObservationIgnored private let cap: Int = 32
    @ObservationIgnored private let stateDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stateDir = docs.appendingPathComponent("BookState", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    // MARK: - Read

    func state(for bookID: UUID) -> ReadingState {
        if let cached = cache[bookID] {
            touch(bookID)
            return cached
        }
        let loaded = loadOrCreate(bookID)
        cache[bookID] = loaded
        accessOrder.append(bookID)
        evictIfNeeded()
        return loaded
    }

    // MARK: - Write

    func update(_ state: ReadingState) {
        cache[state.bookID] = state
        touch(state.bookID)
        save(state)
        revision &+= 1
    }

    func markDirty(_ flags: DirtyFlags, for bookID: UUID) {
        var s = state(for: bookID)
        var current = s.dirtyFlags
        current.insert(flags)
        s.dirtyFlags = current
        update(s)
    }

    func clearDirty(_ flags: DirtyFlags, for bookID: UUID) {
        var s = state(for: bookID)
        var current = s.dirtyFlags
        current.subtract(flags)
        s.dirtyFlags = current
        update(s)
    }

    /// Remove the sidecar for a deleted book.
    func purge(bookID: UUID) {
        cache.removeValue(forKey: bookID)
        accessOrder.removeAll { $0 == bookID }
        try? FileManager.default.removeItem(at: sidecarURL(bookID))
        revision &+= 1
    }

    /// Force-flush a state to disk without touching the cache state. Useful
    /// after merging device data into a state instance you already hold.
    func flush(_ state: ReadingState) {
        cache[state.bookID] = state
        save(state)
        revision &+= 1
    }

    // MARK: - Internal

    private func sidecarURL(_ id: UUID) -> URL {
        stateDir.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadOrCreate(_ id: UUID) -> ReadingState {
        let url = sidecarURL(id)
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(ReadingState.self, from: data) {
            return s
        }
        return ReadingState(bookID: id)
    }

    private func save(_ state: ReadingState) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(state) else { return }
        try? data.write(to: sidecarURL(state.bookID), options: .atomic)
    }

    private func touch(_ id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    private func evictIfNeeded() {
        while accessOrder.count > cap {
            let id = accessOrder.removeFirst()
            cache.removeValue(forKey: id)
        }
    }
}
