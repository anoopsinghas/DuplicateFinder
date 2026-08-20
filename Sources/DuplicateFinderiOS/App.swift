import SwiftUI
import DuplicateFinderCore

@main
struct DuplicateFinderiOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                PhotosScanView()
            }
            .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }

            NavigationStack {
                FilesScanView()
            }
            .tabItem { Label("Files", systemImage: "folder") }
        }
    }
}
