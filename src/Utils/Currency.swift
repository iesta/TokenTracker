import Foundation

let defaultCurrencies: [(code: String, symbol: String, rate: Double, name: String)] = [
    ("USD", "$", 1.0, "US Dollar"),
    ("EUR", "€", 0.92, "Euro"),
    ("GBP", "£", 0.79, "British Pound"),
    ("JPY", "¥", 149.0, "Japanese Yen"),
    ("CAD", "CA$", 1.36, "Canadian Dollar"),
    ("AUD", "A$", 1.53, "Australian Dollar"),
    ("CHF", "Fr", 0.88, "Swiss Franc"),
    ("CNY", "¥", 7.24, "Chinese Yuan"),
    ("INR", "₹", 83.0, "Indian Rupee"),
]

enum SettingsStore {
    static var currencyCode: String {
        get { UserDefaults.standard.string(forKey: "currencyCode") ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: "currencyCode") }
    }
    static var currencyRate: Double {
        get {
            let rate = UserDefaults.standard.double(forKey: "currencyRate")
            return rate > 0 ? rate : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "currencyRate") }
    }
    static var currencySymbol: String {
        let match = defaultCurrencies.first { $0.code == currencyCode }
        return match?.symbol ?? "$"
    }
}

enum CurrencyRates {
    static var cachedRates: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "cachedRates") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "cachedRates") }
    }
    static var lastFetch: Date? {
        get { UserDefaults.standard.object(forKey: "lastRateFetch") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRateFetch") }
    }

    static var lastFetchLabel: String {
        guard let d = lastFetch else { return "never" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func shouldFetch() -> Bool {
        guard let last = lastFetch else { return true }
        return Date().timeIntervalSince(last) > 86400
    }

    static func fetchIfNeeded() {
        guard shouldFetch() else { return }
        Task { await fetch() }
    }

    static func fetch() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double] else { return }
            await MainActor.run {
                cachedRates = rates
                lastFetch = Date()
                let code = SettingsStore.currencyCode
                if code != "USD", let liveRate = rates[code] {
                    SettingsStore.currencyRate = liveRate
                }
            }
        } catch {
            NSLog("CurrencyRates fetch failed: \(error.localizedDescription)")
        }
    }
}