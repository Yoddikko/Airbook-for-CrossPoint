//
//  AirBook_for_CrossPointApp.swift
//  AirBook for CrossPoint
//
//  Created by Ale on 08/06/26.
//

import SwiftUI
import SwiftData

@main
struct AirBook_for_CrossPointApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
