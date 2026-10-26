import Foundation
import DryRunCore

/// Active NWS alerts for Tarrant County from api.weather.gov (public, free; NWS asks for an identifying User-Agent).
/// Only the fixed county zone is sent; nothing about the household. Recorded sample alerts back the filmed demo.
enum WeatherAlertService {
    static let samples = ["tornado", "flash-flood", "heat", "winter"]

    static func fetchActive(zone: String = WeatherAlerts.tarrantCountyZone) async -> [WeatherAlert]? {
        guard let url = URL(string: "https://api.weather.gov/alerts/active?zone=\(zone)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue("DryRun/0.1 (Congressional App Challenge preparedness app; github.com/1unarzDev)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? WeatherAlerts.parse(data)
    }

    static func sample(_ name: String) -> WeatherAlert? {
        guard samples.contains(name), let root = try? ContentLocator.contentRoot(),
              let data = try? Data(contentsOf: root.appendingPathComponent("alerts/sample-\(name).json")) else { return nil }
        return try? WeatherAlerts.parse(data, isSample: true).first
    }
}
