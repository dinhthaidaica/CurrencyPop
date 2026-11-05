import Foundation

// Run with: ./build.sh test
// Digit-only comparisons where a formatter is involved, so the checks pass
// under any locale's grouping and decimal separators.

var failures = 0

func check(_ passed: Bool, _ label: String) {
    print(passed ? "ok   \(label)" : "FAIL \(label)")
    if !passed { failures += 1 }
}

func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.001) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

// evaluate: the arithmetic the amount field has to survive
check(evaluate("100") == 100, "a plain number")
check(evaluate("1250+300*2") == 1850, "precedence: 300*2 before the +")
check(near(evaluate("100/3"), 33.3333), "no integer division")
check(evaluate("12.5*4") == 50, "decimals")
check(evaluate(" 20 + 5 ") == 25, "spaces ignored")

// evaluate: everything that must come back nil instead of crashing
check(evaluate("1250+") == nil, "half-typed expression")
check(evaluate("") == nil, "empty field")
check(evaluate("+") == nil, "operator alone")
check(evaluate("1++2") == nil, "doubled operator")
check(evaluate("(1+2)*3") == nil, "parentheses are out of scope, not a crash")
check(evaluate("1+%d") == nil, "format specifier")
check(evaluate("10%3") == nil, "percent")
check(evaluate("rm -rf /") == nil, "junk")
check(evaluate("1/0") == nil, "division by zero")

// separators: people type "." and "," both ways round
let danish = Locale(identifier: "da_DK"), american = Locale(identifier: "en_US")
check(evaluate("1.234,56") == 1234.56, "both marks: the last one is the decimal")
check(evaluate("1,234.56") == 1234.56, "both marks, the other way round")
check(evaluate("1.000.000") == 1_000_000, "one mark repeated is grouping")
check(evaluate("1,000,000") == 1_000_000, "commas repeated are grouping")
check(evaluate("12,5") == 12.5, "decimal comma")
check(evaluate("12.5") == 12.5, "decimal point")
check(evaluate("0,0125") == 0.0125, "four digits after one mark is decimal")
check(normalizeNumber("1.250", locale: danish) == "1250", "1.250 is grouping where . groups")
check(normalizeNumber("1.250", locale: american) == "1.250", "1.250 is decimal where . is the decimal")
check(normalizeNumber("1,250", locale: danish) == "1.250", "1,250 is decimal where , is the decimal")
check(normalizeNumber("1,250", locale: american) == "1250", "1,250 is grouping where , groups")
check(near(evaluate("1.250,5+10"), 1260.5), "separators inside an expression")
check(evaluate("12,5*2+1,234.5") == 1259.5, "mixed styles across numbers")
check(evaluate("1,2.3,4") == nil, "a decimal mark twice is rejected")
check(evaluate("12,") == nil, "a trailing mark is half-typed")
check(evaluate(",5") == nil, "a leading decimal mark is rejected as before")
check(normalizeNumber(".500", locale: danish) == ".500", "a leading mark is never grouping")
check(evaluate("1..5") == nil, "a doubled mark is a typo, not grouping")
check(evaluate("1.2,3") == nil, "grouping needs three digits after it")
check(evaluate("1.5.2") == nil, "every group needs three digits")
check(evaluate("1,000,000.5") == 1_000_000.5, "valid grouping with a decimal still reads")
check(normalizeNumber("0.125", locale: danish) == "0.125", "a lone 0 is never grouped")
check(normalizeNumber("0,125", locale: american) == "0.125", "a lone 0 is never grouped, comma side")
check(normalizeNumber("1234.567", locale: danish) == "1234.567", "four digits before a mark is not grouping")
check(evaluate("1234.567.890") == nil, "a first group longer than three is malformed")
check(evaluate("10.000.000") == 10_000_000, "a two-digit first group is still grouping")
// main rejected this for the comma; reading the comma must not let the digits through
check(evaluate("1,٢٣٤") == nil, "non-ASCII digits after a mark are rejected too")

// convert
check(near(convert(100, from: "USD", to: "EUR", rates: ["USD": 1.08, "EUR": 1.0]), 92.5926),
      "cross rate through the base currency")
check(convert(5, from: "EUR", to: "EUR", rates: ["EUR": 1.0]) == 5, "same currency is identity")
check(convert(5, from: "XXX", to: "EUR", rates: ["EUR": 1.0]) == nil, "unknown currency")

// formatting
check(fractionDigits("USD") == 2, "USD has cents")
check(fractionDigits("DKK") == 2, "DKK has øre")
check(fractionDigits("VND") == 0, "VND has no minor unit")
check(fractionDigits("JPY") == 0, "JPY has no minor unit")
check(formatAmount(7076250, "VND").filter(\.isNumber) == "7076250", "no decimals on dong")
check(formatAmount(92.5926, "USD").filter(\.isNumber) == "9259", "cents are kept")
// The bug this replaced: a magnitude rule rounded anything over 1000 to whole units.
check(formatAmount(1234.56, "DKK").filter(\.isNumber) == "123456", "a large DKK amount keeps its øre")
check(formatAmount(1234, "USD").filter(\.isNumber) == "123400", "a round amount still shows cents")
check(formatAmount(7076250, "VND").count > 7, "big numbers are grouped")
check(shortDate("2026-10-28") == "28 Oct", "ECB date")
check(shortDate("nonsense") == "nonsense", "unparseable date passes through")

// the shape api.frankfurter.dev actually sends, and the cache round-trip
let payload = Data(#"{"amount":1.0,"base":"EUR","date":"2026-10-27","rates":{"USD":1.1619,"DKK":7.4742}}"#.utf8)
let decoded = try? JSONDecoder().decode(RateSet.self, from: payload)
check(decoded?.date == "2026-10-27", "decodes the API payload")
check(decoded?.rates["DKK"] == 7.4742, "decodes the rate table")
check(decoded?.fetchedAt == nil, "fetchedAt is absent from the API")
if var cached = decoded {
    cached.fetchedAt = Date(timeIntervalSince1970: 1)
    cached.vndDate = "2026-11-04"
    let round = (try? JSONEncoder().encode(cached)).flatMap {
        try? JSONDecoder().decode(RateSet.self, from: $0)
    }
    check(round == cached, "cache survives the round trip")
}
// a cache written before VND existed
let oldCache = Data(#"{"date":"2026-10-27","rates":{"USD":1.1619,"EUR":1.0},"fetchedAt":1}"#.utf8)
let old = try? JSONDecoder().decode(RateSet.self, from: oldCache)
check(old?.rates["USD"] == 1.1619, "an ECB-only cache still decodes")
check(old != nil && old?.vndDate == nil, "an ECB-only cache has no VND date")

// the shape currency-api actually sends, merged into the ECB table
let vndPayload = Data(#"{"date":"2026-11-04","eur":{"usd":1.1224,"vnd":28897.976603,"btc":0.0000105}}"#.utf8)
let quote = try? JSONDecoder().decode(VNDQuote.self, from: vndPayload)
check(quote?.date == "2026-11-04", "decodes the currency-api date")
check(quote?.eur.vnd == 28897.976603, "decodes the VND rate among the others")

let ecb = RateSet(date: "2026-11-03", rates: ["EUR": 1.0, "USD": 1.1619], fetchedAt: nil)
var merged = ecb
merged.addVND(quote, keeping: nil)
check(merged.rates["VND"] == 28897.976603, "VND joins the rate table")
check(merged.vndDate == "2026-11-04", "VND brings its own date")
check(merged.rates["USD"] == 1.1619 && merged.date == "2026-11-03", "ECB rates are untouched")
check(near(convert(100, from: "USD", to: "VND", rates: merged.rates), 2487131.130),
      "USD to VND crosses the merged table through EUR")

var stale = ecb
stale.rates["VND"] = 27000
stale.vndDate = "2026-11-01"
var refreshed = ecb
refreshed.addVND(quote, keeping: stale)
check(refreshed.rates["VND"] == 28897.976603 && refreshed.vndDate == "2026-11-04",
      "a fresh quote replaces the cached one")
var failed = ecb
failed.addVND(nil, keeping: stale)
check(failed.rates["VND"] == 27000 && failed.vndDate == "2026-11-01",
      "a failed VND fetch keeps the cached rate and date")
var none = ecb
none.addVND(nil, keeping: nil)
check(none.rates["VND"] == nil && none.vndDate == nil, "no quote and no cache means no VND")

// the row list the panel stores, and what @AppStorage falls back on
let rows = [Conversion(input: "1250+300*2", from: "DKK", to: "VND"), Conversion()]
check([Conversion](rawValue: rows.rawValue) == rows, "rows survive the round trip")
check([Conversion](rawValue: "[]") == nil, "an empty list is no list, so the default row is used")
check([Conversion](rawValue: "nonsense") == nil, "corrupt storage falls back to the default row")
check(Conversion().id != Conversion().id, "every row has its own identity")
// the exact shape JSONEncoder writes to UserDefaults today, so a format change shows up here
let stored = #"[{"id":"0B5C3E1A-7F4D-4C2B-9E8A-1D2F3A4B5C6D","input":"250","from":"DKK","to":"VND"}]"#
check([Conversion](rawValue: stored)?.first?.id.uuidString == "0B5C3E1A-7F4D-4C2B-9E8A-1D2F3A4B5C6D",
      "a list already on disk still decodes")
check([Conversion](rawValue: stored)?.first?.to == "VND", "a list already on disk keeps its pair")

// version comparison for the update notice
check(isNewer("v1.2", than: "1.1"), "a newer minor")
check(isNewer("v1.10", than: "1.9"), "ten is newer than nine, where a string compare disagrees")
check(isNewer("v2.0", than: "1.9.9"), "a newer major")
check(isNewer("v1.2.1", than: "1.2"), "a newer patch on a two-part version")
check(!isNewer("v1.1", than: "1.1"), "the same version is not newer")
check(!isNewer("v1.0", than: "1.1"), "an older version is not newer")
check(!isNewer("", than: "1.1"), "an empty tag is not newer")
check(!isNewer("nightly", than: "1.1"), "an unparseable tag is not newer")

let releasePayload = Data(#"{"tag_name":"v1.2","html_url":"https://example.com/r/v1.2","name":"x"}"#.utf8)
let release = try? JSONDecoder().decode(LatestRelease.self, from: releasePayload)
check(release?.tagName == "v1.2", "decodes the release tag")
check(release?.htmlUrl == "https://example.com/r/v1.2", "decodes the release page URL")

print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
