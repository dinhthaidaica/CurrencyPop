import Foundation

/// What api.frankfurter.dev returns, plus when we stored it.
/// Every rate is relative to EUR, so one fetch covers every pair.
struct RateSet: Codable, Equatable {
    let date: String                // ECB rate date, "2026-10-28"
    var rates: [String: Double]     // ["USD": 1.08, ...]
    var fetchedAt: Date?            // absent from the API, set when cached
}

/// One row of the panel. The id lets SwiftUI tell rows apart when a middle one
/// is removed; the amount is kept as typed, expression and all.
/// Public only because Swift wants Array's RawRepresentable conformance below
/// public, and that conformance names this type.
public struct Conversion: Codable, Equatable, Identifiable {
    public var id = UUID()
    var input = "100"
    var from = "USD"
    var to = "EUR"
}

/// Lets @AppStorage keep the whole row list as one JSON string.
extension Array: @retroactive RawRepresentable where Element == Conversion {
    /// nil for an empty list as well as a corrupt one, so @AppStorage falls back
    /// to its default row and the panel never opens with no rows at all.
    public init?(rawValue: String) {
        guard let rows = try? JSONDecoder().decode([Conversion].self, from: Data(rawValue.utf8)),
              !rows.isEmpty else { return nil }
        self = rows
    }

    public var rawValue: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
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

/// The two fields we need from api.github.com/repos/.../releases/latest.
struct LatestRelease: Codable, Equatable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

/// Compares "v1.10" against "1.9" numerically, component by component, so the
/// tenth release does not look older than the ninth the way a string compare
/// would have it. Anything unparseable counts as not newer.
func isNewer(_ tag: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.drop(while: { !$0.isNumber }).split(separator: ".").map { Int($0) ?? 0 }
    }
    let new = parts(tag), old = parts(current)
    for i in 0 ..< max(new.count, old.count) {
        let a = i < new.count ? new[i] : 0
        let b = i < old.count ? old[i] : 0
        if a != b { return a > b }
    }
    return false
}

/// One number as typed, with `.` and `,` in whatever role the typist meant,
/// rewritten to the plain "1234.56" form the evaluate regex admits.
///
/// - Both marks present: the last one is the decimal mark ("1.234,56", "1,234.56").
/// - One mark, more than once: grouping ("1.000.000").
/// - One mark, once, after one to three digits and before exactly three
///   ("1.250"): ambiguous, so the locale decides. Its grouping separator means 1250, anything else 1.25.
///   Three-decimal currencies (KWD, BHD) are where this guesses wrong for
///   people whose locale groups with that mark; the "= …" hint shows the reading.
/// - One mark, once, anywhere else: decimal ("12,5", "0.125", "1234.567").
///
/// Anything malformed, a misplaced grouping mark included, comes out still
/// malformed, for the regex to reject.
func normalizeNumber(_ token: String, locale: Locale = .current) -> String {
    // What may stand before a grouping mark: one to three digits, not a lone or
    // leading 0. "0.125" and "1234.567" can only be decimals.
    let isGroupLead = { (s: Substring) in (1...3).contains(s.count) && s.first != "0" }
    let dots = token.filter { $0 == "." }.count
    let commas = token.filter { $0 == "," }.count
    let decimal: Character?
    if dots > 0 && commas > 0 {
        decimal = token.last(where: { $0 == "." || $0 == "," })
    } else if dots + commas == 0 || dots > 1 || commas > 1 {
        decimal = nil
    } else {
        let mark: Character = dots == 1 ? "." : ","
        let parts = token.split(separator: mark, omittingEmptySubsequences: false)
        decimal = isGroupLead(parts[0]) && parts[1].count == 3
            && locale.groupingSeparator == String(mark) ? nil : mark
    }
    // A grouping mark must follow a group lead and come before exactly three
    // digits, or "1..5" and ".500" would quietly become 15 and 500. Returned as typed,
    // such a token always fails the regex, as it did before marks were read.
    let groups = token.split(omittingEmptySubsequences: false) {
        ($0 == "." || $0 == ",") && $0 != decimal
    }
    guard groups.count == 1 || isGroupLead(groups[0])
            && groups.dropFirst().allSatisfy({ $0.prefix(while: \.isNumber).count == 3 })
    else { return token }
    return String(token.compactMap { c -> Character? in
        guard c == "." || c == "," else { return c }
        return c == decimal ? "." : nil
    })
}

/// "1250+300*2" -> 1850. nil while the expression is incomplete or malformed.
///
/// NSExpression raises an Objective-C exception on bad syntax that Swift cannot
/// catch, and a field being typed into is malformed on most keystrokes, so the
/// regex is the whole safety story: only a complete flat expression reaches it.
func evaluate(_ raw: String) -> Double? {
    let s = raw.filter { !$0.isWhitespace }
        .replacing(#/[^-+*\/]+/#) { normalizeNumber(String($0.output)) }
    guard s.range(of: #"^[0-9]+(\.[0-9]+)?([-+*/][0-9]+(\.[0-9]+)?)*$"#,
                  options: .regularExpression) != nil else { return nil }

    // NSExpression does integer division on integer literals ("100/3" -> 33),
    // so give every whole number a decimal point first.
    let decimals = s.replacingOccurrences(of: #"(?<![.0-9])([0-9]+)(?![.0-9])"#,
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

/// What the currency's minor unit is: 2 for USD and DKK, 0 for VND and JPY,
/// 3 for KWD. Foundation already knows, so there is no table to keep current.
func fractionDigits(_ code: String) -> Int {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    return f.maximumFractionDigits
}

/// Grouped, with the decimals the currency actually has.
///
/// Keying this on the size of the number instead — the obvious shortcut, since
/// nobody wants two decimals on a dong total — silently rounded 1234.56 DKK to
/// 1235, on screen and on the clipboard.
func formatAmount(_ value: Double, _ code: String) -> String {
    let digits = fractionDigits(code)
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = digits
    f.minimumFractionDigits = digits
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
