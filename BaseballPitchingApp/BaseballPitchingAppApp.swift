import SwiftData
import SwiftUI

@main
struct BaseballPitchingAppApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            ThrowSession.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Unable to initialize SwiftData model container: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
