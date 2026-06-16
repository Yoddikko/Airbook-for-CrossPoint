import SwiftUI

// MARK: - Metadata Lookup Sheet
//
// Title / author / ISBN search → ranked candidates from Google Books,
// OpenLibrary and iTunes. Tap a row to apply via the `onSelect` closure
// and dismiss.

struct MetadataLookupSheet: View {
    let initialQuery: MetadataQuery
    let onSelect: (MetadataCandidate) -> Void

    @Environment(MetadataLookupService.self) private var lookup
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var isbn: String = ""
    @State private var results: [MetadataCandidate] = []
    @State private var loading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    queryFields
                    Rectangle().fill(Color.paperRule.opacity(0.35)).frame(height: 0.5)

                    if loading {
                        loadingBody
                    } else if let errorMessage {
                        errorBody(errorMessage)
                    } else if results.isEmpty {
                        emptyBody
                    } else {
                        resultList
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Find Metadata")
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color.paperInk)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.paperInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") { runSearch() }
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(Color.paperInk)
                        .disabled(title.isEmpty && author.isEmpty && isbn.isEmpty)
                }
            }
            .toolbarBackground(Color.paperBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if title.isEmpty { title = initialQuery.title ?? "" }
                if author.isEmpty { author = initialQuery.author ?? "" }
                if isbn.isEmpty { isbn = initialQuery.isbn ?? "" }
                if results.isEmpty && (!title.isEmpty || !author.isEmpty || !isbn.isEmpty) {
                    runSearch()
                }
            }
        }
    }

    // MARK: Subviews

    private var queryFields: some View {
        VStack(spacing: 10) {
            field("Title", text: $title)
            field("Author", text: $author)
            field("ISBN", text: $isbn, keyboard: .numbersAndPunctuation)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func field(_ label: String,
                       text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.paperRule)
                .frame(width: 60, alignment: .leading)
            TextField(label, text: text)
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Color.paperInk)
                .keyboardType(keyboard)
                .autocorrectionDisabled(label == "ISBN")
                .textInputAutocapitalization(label == "ISBN" ? .never : .sentences)
                .submitLabel(.search)
                .onSubmit(runSearch)
                .padding(.vertical, 6)
                .overlay(Rectangle().fill(Color.paperRule.opacity(0.35)).frame(height: 0.5),
                         alignment: .bottom)
        }
    }

    private var loadingBody: some View {
        VStack {
            Spacer()
            ProgressView().tint(Color.paperInk)
            Text("Searching…")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.paperRule)
                .padding(.top, 10)
            Spacer()
        }
    }

    private func errorBody(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Color.paperRule)
            Text("Lookup failed")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.paperInk)
            Text(message)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.paperRule)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { runSearch() }
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundStyle(Color.paperInk)
                .padding(.top, 8)
            Spacer()
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No results yet.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.paperRule)
            Text("Enter a title, author, or ISBN and tap Search.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.paperRule)
            Spacer()
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { candidate in
                    VStack(spacing: 0) {
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            ResultRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.paperRule.opacity(0.2))
                            .frame(height: 0.5)
                            .padding(.leading, 88)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: Actions

    private func runSearch() {
        let trimmedIsbn = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        let q = MetadataQuery(
            title: title.isEmpty ? nil : title,
            author: author.isEmpty ? nil : author,
            isbn: trimmedIsbn.isEmpty ? nil : trimmedIsbn)
        guard !q.isEmpty else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let r = try await lookup.search(q)
                await MainActor.run {
                    results = r
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}

// MARK: - Result row

private struct ResultRow: View {
    let candidate: MetadataCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover
                .frame(width: 56, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.paperInk.opacity(0.14), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.title)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(Color.paperInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !candidate.authors.isEmpty {
                    Text(candidate.authors.joined(separator: ", "))
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.paperRule)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
                metaFacts
                if let synopsis = candidate.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(Color.paperInk.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var cover: some View {
        if let url = candidate.coverURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    ZStack {
                        Rectangle().fill(Color.paperRule.opacity(0.12))
                        ProgressView().scaleEffect(0.5).tint(Color.paperRule)
                    }
                default:
                    Rectangle().fill(Color.paperRule.opacity(0.18))
                }
            }
        } else {
            Rectangle().fill(Color.paperRule.opacity(0.18))
        }
    }

    private var metaFacts: some View {
        HStack(spacing: 6) {
            if let year = candidate.publishedYear {
                tag(String(year))
            }
            if let publisher = candidate.publisher, !publisher.isEmpty {
                tag(publisher)
                    .lineLimit(1)
            }
            if let lang = candidate.language, !lang.isEmpty {
                tag(lang.uppercased())
            }
            if let pages = candidate.pageCount {
                tag("\(pages)p")
            }
            Spacer(minLength: 0)
            Text(providerLabel)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.paperRule.opacity(0.7))
        }
    }

    private var providerLabel: String {
        switch candidate.provider {
        case .googleBooks: return "GBOOKS"
        case .openLibrary: return "OPENLIB"
        case .iTunes:      return "ITUNES"
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.paperRule)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(Rectangle().stroke(Color.paperRule.opacity(0.35), lineWidth: 0.4))
    }
}
