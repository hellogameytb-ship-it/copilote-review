import CoreLocation
import Foundation
import MapKit

/// "Lisbonne, Portugal" for a GPS position, in French. Apple's reverse geocoding is a network
/// call: it runs at indexing only, and the index caches every answer by ~1 km square (never on a
/// search). MapKit on macOS 26 (better French names), CLGeocoder before; then French exonyms.
public struct GeocoderPlaceNamer: PlaceNamer {
    public init() {}

    public func name(for coordinate: Coordinate) async throws -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            request.preferredLocale = Locale(identifier: "fr_FR")
            let items: [MKMapItem]
            do {
                items = try await request.mapItems
            } catch let error as MKError where error.code == .placemarkNotFound {
                return nil
            }
            let address = items.first?.addressRepresentations
            return PlaceNames.french(city: address?.cityName, country: address?.regionName)
        }
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "fr_FR"))
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            return nil
        }
        guard let placemark = placemarks.first else { return nil }
        return PlaceNames.french(city: placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea, country: placemark.country)
    }
}
