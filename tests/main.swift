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
    let round = (try? JSONEncoder().encode(cached)).flatMap {
        try? JSONDecoder().decode(RateSet.self, from: $0)
    }
    check(round == cached, "cache survives the round trip")
}

print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
