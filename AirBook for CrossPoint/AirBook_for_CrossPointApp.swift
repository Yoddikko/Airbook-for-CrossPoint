import SwiftUI

@main
struct AirBook_for_CrossPointApp: App {
    @State private var bookStore = BookStore()
    @State private var readingStateStore = ReadingStateStore()
    @State private var collectionsStore = CollectionsStore()
    @State private var metadataLookup = MetadataLookupService()
    @State private var zlib = ZLibService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bookStore)
                .environment(readingStateStore)
                .environment(collectionsStore)
                .environment(metadataLookup)
                .environment(zlib)
        }
    }
}
