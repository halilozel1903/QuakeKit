import QuakeKit
import SwiftUI

/// The selected event: magnitude, place and time at once, then what its detail feed adds:
/// felt reports, intensities, the PAGER alert, the tsunami flag, the location quality, nearby
/// events and the ShakeMap.
struct EventDetailPanel: View {
    let quake: Earthquake
    @Environment(QuakeStore.self) private var store

    var body: some View {
        let state = store.detail(for: quake.id)
        let detail = state.value
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                badges(detail)
                stats(detail)
                switch state {
                case .idle, .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading the event detail…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .loaded:
                    EmptyView()
                }
                nearby
                if let url = detail?.shakemapIntensityImageURL {
                    shakemap(url)
                }
                footer
            }
            .padding(18)
        }
        .task(id: quake.id) {
            await store.loadDetail(for: quake)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            MagnitudeBadge(magnitude: quake.magnitude, size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(quake.place)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(quake.time.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Text("\(quake.relativeTime) · \(quake.magnitudeClass.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func badges(_ detail: EventDetail?) -> some View {
        let alert = detail?.alertLevel ?? quake.alertLevel
        let tsunami = detail?.hasTsunamiFlag ?? quake.hasTsunamiFlag
        let status = quake.properties.status
        HStack(spacing: 6) {
            if let alert {
                InfoChip(text: "PAGER \(alert.name)", systemImage: "exclamationmark.triangle.fill", tint: alert.color.color)
            }
            if tsunami {
                InfoChip(text: "Tsunami flag", systemImage: "water.waves", tint: .cyan)
            }
            if let status {
                InfoChip(
                    text: status == .reviewed ? "Reviewed" : status.rawValue.capitalized,
                    systemImage: status == .reviewed ? "checkmark.seal.fill" : "gearshape",
                    tint: status == .reviewed ? .green : .secondary
                )
            }
        }
        if let alert {
            Text("\(alert.response): estimated fatalities \(alert.estimatedFatalities), losses \(alert.estimatedLosses).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stats(_ detail: EventDetail?) -> some View {
        let felt = detail?.feltReports ?? quake.feltReports
        let reported = detail?.maxReportedIntensity ?? quake.properties.cdi
        let estimated = detail?.maxEstimatedIntensity ?? quake.properties.mmi
        let magnitudeType = detail?.magnitudeType ?? quake.properties.magnitudeType
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatTile(title: "Magnitude", value: quake.magnitude.map { String(format: "%.1f %@", $0, magnitudeType ?? "") } ?? "–")
            StatTile(title: "Depth", value: String(format: "%.1f km", quake.depthKilometers), detail: quake.location.depthClass.rawValue.capitalized)
            StatTile(title: "Felt reports", value: felt.map { $0.formatted() } ?? "None yet", detail: "Did You Feel It?")
            StatTile(
                title: "Intensity",
                value: (estimated ?? reported).map(MercalliIntensity.roman) ?? "–",
                detail: (estimated ?? reported).map(MercalliIntensity.shaking) ?? (estimated == nil ? "Not estimated" : "")
            )
            StatTile(title: "Significance", value: quake.properties.significance.map { $0.formatted() } ?? "–")
            StatTile(
                title: "Stations",
                value: (detail?.stationsUsed ?? quake.properties.stationCount).map { $0.formatted() } ?? "–",
                detail: (detail?.azimuthalGap ?? quake.properties.gap).map { String(format: "Gap %.0f°", $0) }
            )
        }
    }

    @ViewBuilder
    private var nearby: some View {
        let neighbors = store.earthquakes.neighbors(of: quake, within: 300).prefix(4).map {
            Neighbor(earthquake: $0.earthquake, distance: $0.distance, direction: $0.direction)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Within 300 km in this list")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if neighbors.isEmpty {
                Text("No other events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(neighbors) { neighbor in
                    Button {
                        store.selectedID = neighbor.earthquake.id
                    } label: {
                        HStack(spacing: 8) {
                            MagnitudeBadge(magnitude: neighbor.earthquake.magnitude, size: 24)
                            Text("\(neighbor.distance.formatted()) \(neighbor.direction.rawValue)")
                                .font(.caption.weight(.medium))
                            Text(neighbor.earthquake.relativeTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shakemap(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ShakeMap intensity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                QuakeTheme.tileBackground.frame(height: 160)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quake.coordinate.description)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let url = quake.properties.url {
                Link(destination: url) {
                    Label("Event page on earthquake.usgs.gov", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
            }
            Text("Data: U.S. Geological Survey")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct Neighbor: Identifiable {
    let earthquake: Earthquake
    let distance: QuakeDistance
    let direction: CompassPoint

    var id: String { earthquake.id }
}

private struct StatTile: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(QuakeTheme.tileBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
