import QuakeKit
import SwiftUI

/// Quake Watch for iPad: live earthquakes from the USGS feeds and catalog on a map.
@main
struct QuakeWatchApp: App {
    @State private var store = QuakeStore.make(for: ScreenshotScene.current)
    private let scene = ScreenshotScene.current

    var body: some Scene {
        WindowGroup {
            RootView(scene: scene)
                .environment(store)
                .preferredColorScheme(scene == nil ? nil : .dark)
                .tint(QuakeTheme.accent)
        }
    }
}
