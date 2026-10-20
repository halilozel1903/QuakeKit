import MapKit
import QuakeKit
import SwiftUI

/// The detail column: every event of the list on a map as a circle sized and colored by its
/// magnitude, and the selected event's detail in a panel over the map.
struct QuakeMapScreen: View {
    @Environment(QuakeStore.self) private var store
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 760
            ZStack(alignment: wide ? .topTrailing : .bottom) {
                map
                if let quake = store.selected {
                    EventDetailPanel(quake: quake)
                        .id(quake.id)
                        .frame(width: wide ? 380 : nil)
                        .frame(maxHeight: wide ? proxy.size.height - 32 : min(400, proxy.size.height * 0.5))
                        .background(QuakeTheme.panelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                        .padding(16)
                        .transition(.move(edge: wide ? .trailing : .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle(store.selected?.magnitudeLabel ?? "Map")
        .quakeNavigationStyle()
        .onChange(of: store.selectedID, initial: true) {
            focus(on: store.selected)
        }
        .onChange(of: store.source) {
            withAnimation { position = .automatic }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.selectedID = nil
                    withAnimation { position = .automatic }
                } label: {
                    Label("Show All", systemImage: "globe")
                }
                .disabled(store.selectedID == nil)
            }
        }
    }

    private var map: some View {
        // Draw small events first, so large ones are on top.
        let quakes = Array(store.earthquakes.sorted(by: .smallest).suffix(1200))
        let selectedID = store.selectedID
        return Map(position: $position) {
            ForEach(quakes) { quake in
                Annotation(quake.magnitudeLabel, coordinate: quake.coordinate.locationCoordinate, anchor: .center) {
                    QuakeMarker(magnitude: quake.magnitude, isSelected: quake.id == selectedID)
                        .onTapGesture {
                            store.selectedID = quake.id
                        }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private func focus(on quake: Earthquake?) {
        guard let quake else { return }
        let region = MKCoordinateRegion(
            center: quake.coordinate.locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 16, longitudeDelta: 16)
        )
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .region(region)
        }
    }
}

/// A translucent circle in the magnitude's color, sized by the magnitude.
struct QuakeMarker: View {
    let magnitude: Double?
    var isSelected = false

    var body: some View {
        let value = magnitude ?? 0
        let diameter = MagnitudeScale.markerDiameter(for: value) * (isSelected ? 1.25 : 1)
        let color = MagnitudeScale.color(for: value).color
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.9 : 0.62))
            Circle()
                .strokeBorder(isSelected ? Color.white : color, lineWidth: isSelected ? 3 : 1.2)
            if isSelected {
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .frame(width: diameter + 14, height: diameter + 14)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .accessibilityLabel(magnitude.map { String(format: "Magnitude %.1f", $0) } ?? "Earthquake")
    }
}
