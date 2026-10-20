import QuakeKit
import SwiftUI

/// The feed filters: live feeds by magnitude and period, catalog searches, and the color scale.
///
/// On the Mac the sidebar is drawn as plain views on an opaque background instead of a `List`:
/// a translucent sidebar list came out as a blank white panel in window captures.
struct SidebarView: View {
    @Environment(QuakeStore.self) private var store

    var body: some View {
        content
            .navigationTitle("Quakes")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
    }

    #if os(macOS)
    private var content: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                header("Live feeds")
                ForEach(FeedMagnitude.allCases) { magnitude in
                    row(magnitude.title, systemImage: symbol(for: magnitude), item: .feed(magnitude))
                }
                Picker("Period", selection: $store.period) {
                    ForEach(FeedPeriod.allCases) { period in
                        Text(shortTitle(period)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.top, 6)

                header("Catalog search")
                ForEach(CatalogSearch.allCases) { search in
                    row(search.title, systemImage: search.systemImage, item: .catalog(search))
                }

                header("Magnitude scale")
                MagnitudeLegend()
                    .padding(.horizontal, 10)

                Text("Data: U.S. Geological Survey")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QuakeTheme.sidebarBackground.ignoresSafeArea())
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func row(_ title: String, systemImage: String, item: SidebarItem) -> some View {
        let isSelected = store.sidebar == item
        return Button {
            store.sidebar = item
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? QuakeTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #else
    private var content: some View {
        @Bindable var store = store
        return List(selection: Binding<SidebarItem?>(
            get: { store.sidebar },
            set: { if let item = $0 { store.sidebar = item } }
        )) {
            Section("Live feeds") {
                ForEach(FeedMagnitude.allCases) { magnitude in
                    Label(magnitude.title, systemImage: symbol(for: magnitude))
                        .tag(SidebarItem.feed(magnitude))
                }
                Picker("Period", selection: $store.period) {
                    ForEach(FeedPeriod.allCases) { period in
                        Text(shortTitle(period)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Catalog search") {
                ForEach(CatalogSearch.allCases) { search in
                    Label(search.title, systemImage: search.systemImage)
                        .tag(SidebarItem.catalog(search))
                }
            }
            Section {
                MagnitudeLegend()
            } header: {
                Text("Magnitude scale")
            } footer: {
                Text("Data: U.S. Geological Survey")
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    private func symbol(for magnitude: FeedMagnitude) -> String {
        switch magnitude {
        case .all: "circle.grid.3x3.fill"
        case .significant: "star.fill"
        case .m4_5: "waveform.path.ecg"
        case .m2_5: "waveform"
        case .m1_0: "dot.radiowaves.left.and.right"
        }
    }

    private func shortTitle(_ period: FeedPeriod) -> String {
        switch period {
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// The colors of the magnitude classes.
struct MagnitudeLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(MagnitudeClass.allCases.reversed(), id: \.self) { magnitudeClass in
                HStack(spacing: 8) {
                    Circle()
                        .fill(MagnitudeScale.color(for: magnitudeClass).color)
                        .frame(width: 12, height: 12)
                    Text(magnitudeClass.name)
                        .font(.caption)
                    Spacer(minLength: 4)
                    Text(magnitudeClass.rangeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
