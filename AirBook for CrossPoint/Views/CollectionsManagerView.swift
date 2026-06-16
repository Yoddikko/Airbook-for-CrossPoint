import SwiftUI

// MARK: - Collections Manager
//
// Lightweight CRUD view: add new collections, rename, reorder, delete.
// Deleting a collection drops it from the master list — sidecars that
// reference it still keep the name harmlessly until the next edit (the
// chip simply won't appear in the toolbar's filter strip).

struct CollectionsManagerView: View {
    @Environment(CollectionsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @State private var editing: Collection?
    @State private var editingName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    addRow
                    Rectangle().fill(Color.paperRule.opacity(0.35)).frame(height: 0.5)

                    if store.collections.isEmpty {
                        emptyBody
                    } else {
                        listBody
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Collections")
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color.paperInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color.paperInk)
                }
            }
            .toolbarBackground(Color.paperBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Subviews

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("New collection name", text: $newName)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Color.paperInk)
                .submitLabel(.done)
                .onSubmit(addCollection)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Color.paperRule.opacity(0.4), lineWidth: 0.6))

            Button(action: addCollection) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.paperBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.paperInk)
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyBody: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("No collections yet.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.paperRule)
            Text("Add one above to group books.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.paperRule)
            Spacer()
        }
    }

    private var listBody: some View {
        List {
            ForEach(store.collections) { c in
                row(for: c)
                    .listRowBackground(Color.paperBackground)
                    .listRowSeparatorTint(Color.paperRule.opacity(0.2))
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func row(for c: Collection) -> some View {
        if editing?.id == c.id {
            HStack {
                TextField("Name", text: $editingName)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.paperInk)
                    .submitLabel(.done)
                    .onSubmit {
                        store.rename(c, to: editingName)
                        editing = nil
                    }
                Spacer()
                Button("Save") {
                    store.rename(c, to: editingName)
                    editing = nil
                }
                .font(.system(.caption, design: .serif).weight(.bold))
                .foregroundStyle(Color.paperInk)
            }
        } else {
            HStack {
                Text(c.name)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.paperInk)
                Spacer()
                Button {
                    editing = c
                    editingName = c.name
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.paperRule)
                }
            }
        }
    }

    // MARK: Actions

    private func addCollection() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.add(name: name)
        newName = ""
    }

    private func move(from offsets: IndexSet, to dest: Int) {
        var ordered = store.collections
        ordered.move(fromOffsets: offsets, toOffset: dest)
        store.reorder(ordered.map(\.id))
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            let c = store.collections[idx]
            store.remove(c)
        }
    }
}
