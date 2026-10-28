import Foundation

/// What api.frankfurter.dev returns, plus when we stored it.
/// Every rate is relative to EUR, so one fetch covers every pair.
struct RateSet: Codable, Equatable {
    let date: String                // ECB rate date, "2026-10-28"
    var rates: [String: Double]     // ["USD": 1.08, ...]
    var fetchedAt: Date?            // absent from the API, set when cached
}

/// Shown until the first fetch answers; after that the live rate table decides,
/// because the ECB does drop currencies (BGN left when Bulgaria joined the euro).
let fallbackCurrencies = ["AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP",
                          "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN",
                          "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB",
                          "TRY", "USD", "ZAR"]

func currencyName(_ code: String) -> String {
    Locale.current.localizedString(forCurrencyCode: code) ?? code
}

/// "1250+300*2" -> 1850. nil while the expression is incomplete or malformed.
///
/// NSExpression raises an Objective-C exception on bad syntax that Swift cannot
/// catch, and a field being typed into is malformed on most keystrokes, so the
/// regex is the whole safety story: only a complete flat expression reaches it.
func evaluate(_ raw: String) -> Double? {
    let s = raw.filter { !$0.isWhitespace }
    guard s.range(of: #"^\d+(\.\d+)?([-+*/]\d+(\.\d+)?)*$"#,
                  options: .regularExpression) != nil else { return nil }

    // NSExpression does integer division on integer literals ("100/3" -> 33),
    // so give every whole number a decimal point first.
    let decimals = s.replacingOccurrences(of: #"(?<![.\d])(\d+)(?![.\d])"#,
                                          with: "$1.0", options: .regularExpression)
    let value = (NSExpression(format: decimals)
        .expressionValue(with: nil, context: nil) as? NSNumber)?.doubleValue
    return value.flatMap { $0.isFinite ? $0 : nil }
}

/// Cross rate through whatever currency the rate table is based on.
func convert(_ amount: Double, from: String, to: String, rates: [String: Double]) -> Double? {
    guard let f = rates[from], let t = rates[to], f != 0 else { return nil }
    return amount / f * t
}

/// Grouped, and only as precise as the size of the number deserves.
func formatAmount(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = abs(value) >= 1000 ? 0 : 2
    f.minimumFractionDigits = 0
    return f.string(from: value as NSNumber) ?? "—"
}

/// A single unit rate, where the interesting digits sit further right.
func formatRate(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = value >= 100 ? 2 : (value >= 1 ? 4 : 6)
    f.minimumFractionDigits = 2
    return f.string(from: value as NSNumber) ?? "—"
}

/// "2026-10-28" -> "28 Oct". The ECB publishes dates, not timestamps.
func shortDate(_ iso: String) -> String {
    let parts = iso.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month),
          let day = Int(parts[2]) else { return iso }
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(day) \(months[month - 1])"
}
