import Foundation
import SwiftUI

/// Scenes used by CI to capture the README screenshots on an iPad simulator and on the Mac.
/// Launch with `-screenshot <scene>` (an `ipad-` or `mac-` prefix is ignored); normal launches are
/// unaffected.
///
/// Every scene loads live data from the USGS summary feeds and FDSN event service at
/// earthquake.usgs.gov, and live Apple Maps tiles. Nothing is bundled or faked; if a request fails
/// the scene never reports ready and CI fails.
enum ScreenshotScene: String, CaseIterable, Sendable {
    /// iPad and Mac: the M2.5+ feed of the past 7 days in the list and on the map.
    case map
    /// iPad: the strongest event of the M4.5+ week feed on the map with its detail panel.
    case detail
    /// Mac: a catalog search for M6+ in the past year, largest first, with the top event's detail.
    case list

    static var current: ScreenshotScene? {
        guard var name = argument(after: "-screenshot") else { return nil }
        for prefix in ["ipad-", "mac-"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return ScreenshotScene(rawValue: name)
    }

    /// How long to wait after the data is on screen before reporting ready, so MapKit can load
    /// and draw its tiles. SwiftUI's `Map` has no "finished rendering" callback.
    static let mapSettleSeconds: Double = 12

    /// Where to write the ready marker: `-screenshot-ready-file <path>` (the Mac script passes
    /// one), or `tmp/screenshot-ready` in the app's container (what the iPad script watches).
    static var readyMarkerURL: URL {
        if let path = argument(after: "-screenshot-ready-file") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshot-ready")
    }

    static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// Called once a screenshot scene is on screen with its data, on the Mac to capture the window.
@MainActor
enum ScreenshotReadiness {
    static var onReady: (@MainActor (ScreenshotScene) -> Void)?
}

extension View {
    /// Tells the screenshot scripts that the scene is on screen by writing the ready marker, once
    /// `isReady` is true (the live data has loaded) and then the map has had
    /// ``ScreenshotScene/mapSettleSeconds`` to load its tiles. Nothing is written when loading
    /// fails, so CI fails instead of committing a broken capture.
    func signalsScreenshotReady(_ scene: ScreenshotScene?, when isReady: Bool) -> some View {
        task(id: isReady) {
            guard let scene, isReady, ScreenshotScene.current == scene else { return }
            print("Screenshot scene \(scene.rawValue): data loaded, waiting \(Int(ScreenshotScene.mapSettleSeconds)) s for map tiles")
            do {
                try await Task.sleep(for: .seconds(ScreenshotScene.mapSettleSeconds))
            } catch {
                return
            }
            do {
                try scene.rawValue.write(to: ScreenshotScene.readyMarkerURL, atomically: true, encoding: .utf8)
                print("Screenshot scene \(scene.rawValue) is ready")
            } catch {
                print("Could not write the ready marker: \(error)")
            }
            await MainActor.run {
                ScreenshotReadiness.onReady?(scene)
            }
        }
    }
}
