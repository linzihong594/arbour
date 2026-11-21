import DiaryCore
import MapKit
import SwiftUI

/// Created only while the sheet is presented; the map is never kept in the editor hierarchy.
///
/// The selection is the map centre. SwiftUI's `Map` on macOS kept the camera callback from firing
/// during a user pan, so this uses an `MKMapView` wrapper whose region delegate reports every move.
/// Clicking the map also recentres it on the clicked point.
struct LocationMapPicker: View {
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)

    let onConfirm: (DiaryLocation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var initialCenter: CLLocationCoordinate2D
    @State private var selected: CLLocationCoordinate2D

    init(initial: DiaryLocation?, onConfirm: @escaping (DiaryLocation) -> Void) {
        self.onConfirm = onConfirm
        let center =
            initial.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            ?? Self.fallbackCenter
        _initialCenter = State(initialValue: center)
        _selected = State(initialValue: center)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("在地图上选点", "Pick Location on Map")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L10n.tr("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            PickerMapView(initialCenter: initialCenter, selected: $selected)
                .overlay(alignment: .center) {
                    Image(systemName: "scope")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(DiaryStyle.accent)
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel(L10n.tr("地图，拖动或点击选择位置", "Map, drag or click to pick a location"))
                .frame(minWidth: 560, minHeight: 360)

            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(DiaryStyle.accent)
                Text(String(format: "%.4f, %.4f", selected.latitude, selected.longitude))
                    .font(.system(size: 12, design: .monospaced))
                Text(L10n.tr("拖动或点击地图选择位置，中心准星即所选点", "Drag or click the map; the center reticle is selected"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("使用此位置", "Use Location")) {
                    onConfirm(
                        DiaryLocation(
                            latitude: selected.latitude,
                            longitude: selected.longitude,
                            horizontalAccuracy: 0,
                            capturedAt: .now,
                            source: .manual))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}

private struct PickerMapView: NSViewRepresentable {
    let initialCenter: CLLocationCoordinate2D
    @Binding var selected: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator(selected: $selected) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.setRegion(
            MKCoordinateRegion(
                center: initialCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)),
            animated: false)
        let click = NSClickGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        map.addGestureRecognizer(click)
        return map
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private let selected: Binding<CLLocationCoordinate2D>

        init(selected: Binding<CLLocationCoordinate2D>) { self.selected = selected }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            selected.wrappedValue = mapView.centerCoordinate
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            map.setCenter(coordinate, animated: true)
            selected.wrappedValue = coordinate
        }
    }
}
