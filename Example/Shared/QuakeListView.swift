import QuakeKit
import SwiftUI

/// The events of the current feed or search, with a summary header and a sort menu.
struct QuakeListView: View {
    @Environment(QuakeStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.feed {
            case .idle, .loading:
                ProgressView("Loading earthquakes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load earthquakes", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await store.load() }
                    }
                }
            case let .loaded(feed):
                if feed.earthquakes.isEmpty {
                    ContentUnavailableView(
                        "No earthquakes",
                        systemImage: "checkmark.seal",
                        description: Text("Nothing matches \(store.source.title) right now.")
                    )
                } else {
                    List(selection: $store.selectedID) {
                        Section {
                            ForEach(store.earthquakes) { quake in
                                QuakeRow(quake: quake)
                                    .tag(quake.id)
                            }
                        } header: {
                            ListSummary(feed: feed, total: store.total)
                        }
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #else
                    .listStyle(.plain)
                    #endif
                }
            }
        }
        .navigationTitle(store.source.title)
        .quakeNavigationStyle()
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $store.order) {
                        ForEach(EarthquakeOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem {
                Button {
                    Task { await store.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.feed.isLoading)
            }
        }
    }
}

/// How many events, when the feed was generated, and the total of a catalog search.
private struct ListSummary: View {
    let feed: QuakeFeed
    let total: EventCount?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let generated = feed.metadata.generated {
                Text("Updated \(generated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private var countText: String {
        let shown = feed.earthquakes.count
        let noun = shown == 1 ? "earthquake" : "earthquakes"
        if let total, total.count > shown {
            return "\(shown.formatted()) of \(total.count.formatted()) \(noun) in the catalog"
        }
        if let total {
            return "\(total.count.formatted()) \(noun) in the catalog"
        }
        return "\(shown.formatted()) \(noun)"
    }
}

/// One event: magnitude badge, place, time, depth and flags.
struct QuakeRow: View {
    let quake: Earthquake

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MagnitudeBadge(magnitude: quake.magnitude)
            VStack(alignment: .leading, spacing: 3) {
                Text(quake.place)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(quake.relativeTime)
                    Text("·")
                    Text(String(format: "%.0f km deep", quake.depthKilometers))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if quake.alertLevel != nil || quake.hasTsunamiFlag || (quake.feltReports ?? 0) > 0 {
                    HStack(spacing: 6) {
                        if let alert = quake.alertLevel {
                            InfoChip(text: alert.name, systemImage: "exclamationmark.triangle.fill", tint: alert.color.color)
                        }
                        if quake.hasTsunamiFlag {
                            InfoChip(text: "Tsunami", systemImage: "water.waves", tint: .cyan)
                        }
                        if let felt = quake.feltReports, felt > 0 {
                            InfoChip(text: felt.formatted(), systemImage: "person.2.fill", tint: .secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
