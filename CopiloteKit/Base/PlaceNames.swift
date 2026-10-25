import Foundation

/// "Lisbonne, Portugal": the place of a photo as a French speaker says it.
public enum PlaceNames {
    public static func french(city: String?, country: String?) -> String? {
        let city = city.map { exonyms[$0] ?? $0 }
        let parts = [city, country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Cities Apple's geocoder leaves in their own language even with a French locale.
    static let exonyms: [String: String] = [
        "Lisboa": "Lisbonne", "Sevilla": "Séville", "Barcelona": "Barcelone", "Zaragoza": "Saragosse", "Córdoba": "Cordoue",
        "München": "Munich", "Köln": "Cologne", "Aachen": "Aix-la-Chapelle", "Wien": "Vienne", "Praha": "Prague",
        "Warszawa": "Varsovie", "Kraków": "Cracovie", "København": "Copenhague", "Göteborg": "Göteborg",
        "Roma": "Rome", "Milano": "Milan", "Venezia": "Venise", "Firenze": "Florence", "Napoli": "Naples",
        "Torino": "Turin", "Genova": "Gênes", "London": "Londres", "Edinburgh": "Édimbourg", "Den Haag": "La Haye",
        "Antwerpen": "Anvers", "Basel": "Bâle", "Zürich": "Zurich", "Athína": "Athènes", "Moskva": "Moscou",
        "Beijing": "Pékin", "Ciudad de México": "Mexico", "New York City": "New York",
    ]
}
