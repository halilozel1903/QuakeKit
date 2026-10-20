import QuakeKit
import SwiftUI

/// The whole app, on iPad and on the Mac: feed filters in the sidebar, the events in the
/// middle column and the map with the selected event's detail on the right.
struct RootView: View {
    let scene: ScreenshotScene?

    @Environment(QuakeStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(scene: ScreenshotScene?) {
        self.scene = scene
        #if os(iOS)
        // iPad scenes: the list beside the map, or the map full width with the detail panel.
        let visibility: NavigationSplitViewVisibility = switch scene {
        case .some(.map): .doubleColumn
        case .some(.detail): .detailOnly
        default: .automatic
        }
        #else
        let visibility: NavigationSplitViewVisibility = .all
        #endif
        _columnVisibility = State(initialValue: visibility)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            QuakeListView()
        } detail: {
            QuakeMapScreen()
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: store.source) {
            await store.load()
        }
        .onChange(of: store.source) {
            store.reset()
        }
        .signalsScreenshotReady(scene, when: store.isReady(for: scene))
    }
}
