import SwiftUI

@main
struct NirogApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea()
                .background(Color(red: 1.0, green: 0.969, blue: 0.925))
        }
    }
}
