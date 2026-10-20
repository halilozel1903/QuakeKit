import Foundation
import Observation
import QuakeKit

/// The app's data, all from one `QuakeClient` on the live USGS services: what the sidebar
/// selected, the loaded events, the selected event and the details loaded so far.
@Observable
@MainActor
final class QuakeStore {
    let client: QuakeClient

    var sidebar: SidebarItem = .feed(.m2_5)
    var period: FeedPeriod = .week
    var order: EarthquakeOrder = .newest
    var selectedID: Earthquake.ID?

    private(set) var feed: Loadable<QuakeFeed> = .idle
    /// For catalog searches: how many events match in total.
    private(set) var total: EventCount?
    private(set) var details: [Earthquake.ID: Loadable<EventDetail>] = [:]

    /// Select this after the next load: the strongest event, or the first in the list order.
    var autoSelect: AutoSelect?
    enum AutoSelect {
        case strongest
        case first
    }

    /// How many times a request is tried before the error is shown.
    private let attempts: Int

    init(client: QuakeClient = QuakeClient(), attempts: Int = 1) {
        self.client = client
        self.attempts = max(1, attempts)
    }

    /// The live services; screenshot scenes start on a fixed source and retry failed requests a
    /// few times, since a capture must not show an error.
    static func make(for scene: ScreenshotScene?) -> QuakeStore {
        let store = QuakeStore(
            client: QuakeClient(configuration: QuakeConfiguration(userAgent: "QuakeWatch/1.0 (+https://github.com/halilozel1903/QuakeKit) QuakeKit/1.0")),
            attempts: scene == nil ? 1 : 4
        )
        switch scene {
        case .map:
            store.sidebar = .feed(.m2_5)
            store.period = .week
        case .detail:
            store.sidebar = .feed(.m4_5)
            store.period = .week
            store.autoSelect = .strongest
        case .list:
            store.sidebar = .catalog(.strongYear)
            store.order = .largest
            store.autoSelect = .first
        case nil:
            break
        }
        return store
    }

    // MARK: - Derived

    /// What is loaded for the current selection.
    var source: Source {
        switch sidebar {
        case let .feed(magnitude): .feed(SummaryFeed(magnitude, period))
        case let .catalog(search): .catalog(search)
        }
    }

    enum Source: Hashable {
        case feed(SummaryFeed)
        case catalog(CatalogSearch)

        var title: String {
            switch self {
            // Short enough for the list column's title next to its toolbar buttons.
            case let .feed(feed): feed.magnitude.title + " · " + feed.period.rawValue.capitalized
            case let .catalog(search): search.title
            }
        }
    }

    var earthquakes: [Earthquake] {
        feed.value?.sorted(by: order) ?? []
    }

    var selected: Earthquake? {
        guard let selectedID else { return nil }
        return feed.value?.earthquakes.first { $0.id == selectedID }
    }

    func detail(for id: Earthquake.ID) -> Loadable<EventDetail> {
        details[id] ?? .idle
    }

    // MARK: - Loading

    /// Loads the current source. Called whenever it changes, and to refresh.
    func load() async {
        let source = self.source
        if feed.value == nil { feed = .loading }
        let client = self.client
        let attempts = self.attempts
        do {
            let result: QuakeFeed
            switch source {
            case let .feed(summary):
                result = try await Self.retrying(attempts: attempts) { try await client.feed(summary) }
                total = nil
            case let .catalog(search):
                let query = search.query()
                async let events = Self.retrying(attempts: attempts) { try await client.events(query) }
                async let count = Self.retrying(attempts: attempts) { try await client.count(query) }
                result = try await events
                total = try? await count
            }
            guard source == self.source else { return }
            feed = .loaded(result)
            applyAutoSelect(result)
            if let selectedID, !result.earthquakes.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard source == self.source, !Task.isCancelled else { return }
            feed = .failed(error.localizedDescription)
        }
    }

    /// Clears the list before loading another source.
    func reset() {
        feed = .loading
        total = nil
        selectedID = nil
    }

    private func applyAutoSelect(_ result: QuakeFeed) {
        guard let autoSelect else { return }
        self.autoSelect = nil
        switch autoSelect {
        case .strongest:
            selectedID = result.strongest?.id
        case .first:
            selectedID = result.sorted(by: order).first?.id
        }
    }

    /// Loads the detail of an event once; failures can be retried by calling again.
    func loadDetail(for earthquake: Earthquake) async {
        if case .loaded = detail(for: earthquake.id) { return }
        if case .loading = detail(for: earthquake.id) { return }
        details[earthquake.id] = .loading
        let client = self.client
        let attempts = self.attempts
        do {
            let detail = try await Self.retrying(attempts: attempts) { try await client.detail(for: earthquake) }
            details[earthquake.id] = .loaded(detail)
        } catch {
            details[earthquake.id] = .failed(error.localizedDescription)
        }
    }

    /// Runs `operation`, trying again after a pause when it fails, up to `attempts` times.
    nonisolated static func retrying<T: Sendable>(
        attempts: Int,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < attempts, !Task.isCancelled else { throw error }
                print("Request failed (attempt \(attempt) of \(attempts)): \(error)")
                try await Task.sleep(for: .seconds(Double(attempt) * 3))
                attempt += 1
            }
        }
    }

    // MARK: - Screenshots

    /// Whether a screenshot scene has everything it shows: the events, and for scenes with a
    /// selection, the selected event's detail.
    func isReady(for scene: ScreenshotScene?) -> Bool {
        guard let scene, let feed = feed.value, !feed.earthquakes.isEmpty else { return false }
        switch scene {
        case .map:
            return true
        case .detail, .list:
            guard let selectedID else { return false }
            return detail(for: selectedID).value != nil
        }
    }
}
