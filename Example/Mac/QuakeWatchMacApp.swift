import QuakeKit
import SwiftUI

/// Quake Watch for the Mac: live earthquakes from the USGS feeds and catalog on a map.
@main
struct QuakeWatchMacApp: App {
    @State private var store = QuakeStore.make(for: ScreenshotScene.current)
    private let scene = ScreenshotScene.current

    var body: some Scene {
        WindowGroup("Quake Watch") {
            RootView(scene: scene)
                .environment(store)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(scene == nil ? nil : .dark)
                .tint(QuakeTheme.accent)
                .background {
                    if let scene {
                        ScreenshotWindow(scene: scene)
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
    }
}
