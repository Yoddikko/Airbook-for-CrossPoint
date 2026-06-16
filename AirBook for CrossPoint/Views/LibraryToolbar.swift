import SwiftUI

// MARK: - Library Toolbar
//
// Search field + sort menu + horizontal chip strip for collections, device
// state, and format filters. Sits directly under the masthead, above the
// grid. Empty/default state collapses to just the search field so the UI
// stays calm when there's nothing to filter.

struct LibraryToolbar: View {
    @Binding var query: LibraryQuery
    let availableCollections: [Collection]
    let availableFormats: [String]

    @State private var showingSortSheet = false
    @State private var showingManager = false

    var body: some View {
        VStack(spacing: 8) {
            searchRow

            if !availableCollections.isEmpty || query.filterDeviceState != .any || !query.filterFormat.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deviceStateChips
                        collectionChips
                        formatChips
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showingSortSheet) {
            SortSheet(sortField: $query.sortField, ascending: $query.sortAscending)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingManager) {
            CollectionsManagerView()
        }
    }

    // MARK: Rows

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.paperRule)
                TextField("Search title or author", text: $query.searchText)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color.paperInk)
                    .submitLabel(.search)
                if !query.searchText.isEmpty {
                    Button {
                        query.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Color.paperRule)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Rectangle().stroke(Color.paperRule.opacity(0.4), lineWidth: 0.6))

            Button {
                showingSortSheet = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.paperInk)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().stroke(Color.paperInk, lineWidth: 0.8))
            }

            Button {
                showingManager = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.paperInk)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().stroke(Color.paperInk, lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 20)
    }

    private var deviceStateChips: some View {
        ForEach(DeviceStateFilter.allCases, id: \.self) { f in
            chip(text: f.label,
                 selected: query.filterDeviceState == f,
                 destructive: false) {
                query.filterDeviceState = f
            }
        }
    }

    private var collectionChips: some View {
        ForEach(availableCollections) { c in
            chip(text: c.name,
                 selected: query.filterCollections.contains(c.name),
                 destructive: false) {
                if query.filterCollections.contains(c.name) {
                    query.filterCollections.remove(c.name)
                } else {
                    query.filterCollections.insert(c.name)
                }
            }
        }
    }

    private var formatChips: some View {
        ForEach(availableFormats, id: \.self) { f in
            chip(text: f.uppercased(),
                 selected: query.filterFormat.contains(f),
                 destructive: false) {
                if query.filterFormat.contains(f) {
                    query.filterFormat.remove(f)
                } else {
                    query.filterFormat.insert(f)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(text: String, selected: Bool, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(selected ? Color.paperBackground : Color.paperInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected ? Color.paperInk : Color.paperBackground)
                .overlay(Rectangle().stroke(Color.paperInk, lineWidth: 0.6))
        }
    }
}

// MARK: - Sort sheet

struct SortSheet: View {
    @Binding var sortField: SortField
    @Binding var ascending: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    ForEach(SortField.allCases, id: \.self) { f in
                        Button {
                            if sortField == f {
                                ascending.toggle()
                            } else {
                                sortField = f
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Text(f.label)
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(Color.paperInk)
                                Spacer()
                                if sortField == f {
                                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.paperInk)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                        }
                        Rectangle().fill(Color.paperRule.opacity(0.2)).frame(height: 0.5)
                            .padding(.leading, 24)
                    }
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Sort By")
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color.paperInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.paperInk)
                }
            }
            .toolbarBackground(Color.paperBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
