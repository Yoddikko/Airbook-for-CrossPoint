import SwiftUI

@main
struct AirBook_for_CrossPointApp: App {
    @State private var bookStore = BookStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bookStore)
        }
    }
}
