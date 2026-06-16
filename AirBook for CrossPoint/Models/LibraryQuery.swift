import Foundation

// MARK: - Sort / filter axes

enum SortField: String, CaseIterable, Equatable, Codable {
    case title
    case author
    case addedDate
    case fileSize
    case percentRead

    var label: String {
        switch self {
        case .title:       return "Title"
        case .author:      return "Author"
        case .addedDate:   return "Date Added"
        case .fileSize:    return "File Size"
        case .percentRead: return "% Read"
        }
    }
}

enum DeviceStateFilter: String, CaseIterable, Equatable, Codable {
    case any
    case onlyOnDevice
    case onlyMissingFromDevice
    case onlyFreed

    var label: String {
        switch self {
        case .any:                   return "Any"
        case .onlyOnDevice:          return "On Device"
        case .onlyMissingFromDevice: return "Not Synced"
        case .onlyFreed:             return "Freed"
        }
    }
}

// MARK: - Library Query
//
// Pure value type: the toolbar mutates it via @State, the BookStore.books
// list is filtered through it inside the view body. Apply runs O(N) over
// the library so we keep it lean enough for 5K-book lists.

struct LibraryQuery: Equatable {
    var searchText: String = ""
    var sortField: SortField = .addedDate
    var sortAscending: Bool = false
    /// AND semantics: a book must contain ALL of these collection names.
    var filterCollections: Set<String> = []
    var filterDeviceState: DeviceStateFilter = .any
    var filterFormat: Set<String> = []

    var isDefault: Bool {
        searchText.isEmpty &&
        filterCollections.isEmpty &&
        filterDeviceState == .any &&
        filterFormat.isEmpty &&
        sortField == .addedDate &&
        !sortAscending
    }

    func apply(to books: [Book],
               readingStateStore: ReadingStateStore,
               deviceStates: [UUID: DeviceFileState]) -> [Book] {

        var result = books

        // Text search: title (display or override) + author.
        if !searchText.isEmpty {
            result = result.filter { book in
                if book.displayTitle.localizedCaseInsensitiveContains(searchText) { return true }
                if let author = book.metadata.author,
                   author.localizedCaseInsensitiveContains(searchText) { return true }
                return false
            }
        }

        // Collection intersection.
        if !filterCollections.isEmpty {
            result = result.filter { book in
                let owned = Set(readingStateStore.state(for: book.id).collections)
                return filterCollections.isSubset(of: owned)
            }
        }

        // Device-state slice.
        switch filterDeviceState {
        case .any:
            break
        case .onlyOnDevice:
            result = result.filter { deviceStates[$0.id]?.isOnDevice == true }
        case .onlyMissingFromDevice:
            result = result.filter { state in
                guard let s = deviceStates[state.id] else { return true }
                return !s.isOnDevice
            }
        case .onlyFreed:
            result = result.filter { deviceStates[$0.id] == .entryOnly }
        }

        // Format chips.
        if !filterFormat.isEmpty {
            result = result.filter { filterFormat.contains($0.ext) }
        }

        // Sort.
        switch sortField {
        case .title:
            result.sort {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .author:
            result.sort {
                let a = $0.metadata.author ?? ""
                let b = $1.metadata.author ?? ""
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        case .addedDate:
            result.sort { $0.addedDate < $1.addedDate }
        case .fileSize:
            result.sort { $0.fileSize < $1.fileSize }
        case .percentRead:
            result.sort {
                let a = readingStateStore.state(for: $0.id).progress?.percentage ?? 0
                let b = readingStateStore.state(for: $1.id).progress?.percentage ?? 0
                return a < b
            }
        }

        if !sortAscending {
            result.reverse()
        }
        return result
    }
}
