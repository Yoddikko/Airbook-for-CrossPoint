import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root Library View

struct ContentView: View {
    @Environment(BookStore.self) private var store
    @State private var showingPicker = false
    @State private var selectedBook: Book?
    @State private var importErrorMessage: String?
    @State private var showingImportError = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.airBookBackground.ignoresSafeArea()

                Group {
                    if store.books.isEmpty {
                        EmptyLibraryView { showingPicker = true }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(store.books) { book in
                                    BookCardView(book: book)
                                        .onTapGesture { selectedBook = book }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                store.deleteBook(book)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("AirBook")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPicker = true } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.airBookAccent)
                    }
                }
            }
        }
        .sheet(item: $selectedBook) { book in
            SendView(book: book)
                .environment(store)
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPickerView { url in
                do {
                    _ = try store.importBook(from: url)
                } catch {
                    importErrorMessage = error.localizedDescription
                    showingImportError = true
                }
            }
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
    }
}

// MARK: - Book Card

struct BookCardView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(book: book)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(Color.primary)

                Text(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Book Cover Placeholder

struct BookCoverView: View {
    let book: Book

    var coverColor: Color {
        let palette: [Color] = [
            Color(red: 0.34, green: 0.24, blue: 0.71),
            Color(red: 0.20, green: 0.42, blue: 0.78),
            Color(red: 0.64, green: 0.22, blue: 0.61),
            Color(red: 0.14, green: 0.56, blue: 0.52),
            Color(red: 0.76, green: 0.33, blue: 0.14),
            Color(red: 0.18, green: 0.54, blue: 0.30),
            Color(red: 0.70, green: 0.17, blue: 0.34),
            Color(red: 0.44, green: 0.29, blue: 0.13),
        ]
        let hash = book.filename.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [coverColor, coverColor.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle stripe texture
            VStack(spacing: 10) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.04))
                        .frame(height: 1)
                }
            }
            .frame(maxHeight: .infinity)

            // Title + badge
            VStack(alignment: .leading, spacing: 5) {
                Text(book.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.5), radius: 2)

                Text(book.ext.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Empty State

struct EmptyLibraryView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 72))
                .foregroundStyle(
                    Color.airBookAccent.opacity(0.5),
                    Color.airBookAccent.opacity(0.25)
                )

            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(.title3.weight(.semibold))

                Text("Import EPUB, TXT, or BMP files\nto send them to your CrossPoint.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAdd) {
                Label("Add Book", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.airBookAccent)
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .text, .item])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Design Tokens

extension Color {
    // Warm parchment in light mode, system grouped background in dark mode
    static let airBookBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground
            : UIColor(red: 0.979, green: 0.961, blue: 0.938, alpha: 1)
    })

    // Deep purple in light mode, lighter purple in dark mode for legibility
    static let airBookAccent = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.52, blue: 0.92, alpha: 1)
            : UIColor(red: 0.341, green: 0.243, blue: 0.710, alpha: 1)
    })
}
