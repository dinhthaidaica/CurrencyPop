import SwiftUI
import AppKit

// MARK: - Model

/// The one accent in the panel, dark enough to read on white and light enough on black.
let accent = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.37, green: 0.83, blue: 0.72, alpha: 1)
        : NSColor(srgbRed: 0.05, green: 0.39, blue: 0.33, alpha: 1)
})

// MARK: - App

@main
struct CurrencyPopApp: App {
    var body: some Scene {
        MenuBarExtra("CurrencyPop", systemImage: "arrow.left.arrow.right") {
            ConverterView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Panel

struct ConverterView: View {
    @AppStorage("input") private var input = "100"
    @AppStorage("from") private var from = "USD"
    @AppStorage("to") private var to = "EUR"
    @AppStorage("cachedRates") private var cachedRates = ""

    @State private var rates: RateSet?
    @State private var displayed: Double?   // last good result, kept while you retype
    @State private var offline = false
    @State private var swapAngle = 0.0
    @State private var copied = false
    @FocusState private var amountFocused: Bool

    /// nil while the expression is half-typed.
    private var amount: Double? { evaluate(input) }

    private var result: Double? {
        guard let amount, let rates else { return nil }
        return convert(amount, from: from, to: to, rates: rates.rates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            amountLabel
            amountField
            pickerRow
            Divider().padding(.vertical, 2)
            resultBlock
        }
        .padding(14)
        .frame(width: 318)
        .tint(accent)
        .onChange(of: result) { _, new in if let new { displayed = new } }
        .onAppear {
            displayed = result
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { amountFocused = true }
        }
        .task { await loadRates() }
    }

    // MARK: Amount

    private var amountLabel: some View {
        HStack {
            Text("AMOUNT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            if let subtotal {
                Text("= " + subtotal)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(accent)
                    // Dimmed, not gone: a half-typed expression should not make the
                    // panel twitch on every keystroke.
                    .opacity(amount == nil ? 0.35 : 1)
            }
        }
    }

    /// The running total, shown only when the field holds more than a plain number.
    @State private var lastSubtotal: String?
    private var subtotal: String? {
        guard let amount else { return lastSubtotal }
        let formatted = formatAmount(amount)
        return formatted == input.filter { !$0.isWhitespace } ? nil : formatted
    }

    private var amountField: some View {
        HStack(spacing: 8) {
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 24, design: .monospaced))
                .focused($amountFocused)
                .onChange(of: input) { _, _ in lastSubtotal = subtotal }
            Text(from)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    // MARK: Currencies

    private var pickerRow: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                picker($from)
                picker($to)
            }
            Button(action: swap) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(accent.opacity(0.14)))
                    .rotationEffect(.degrees(swapAngle))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Swap currencies (⌘S)")
        }
    }

    /// Whatever today's rate table actually holds; the static list only covers
    /// the moments before the first fetch answers.
    private var available: [String] {
        rates.map { $0.rates.keys.sorted() } ?? fallbackCurrencies
    }

    private func picker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(available, id: \.self) { code in
                Text("\(code)   \(currencyName(code))").tag(code)
            }
        }
        .labelsHidden()
    }

    private func swap() {
        (from, to) = (to, from)
        withAnimation(.easeInOut(duration: 0.25)) { swapAngle += 180 }
    }

    // MARK: Result

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(copied ? "COPIED" : "CONVERTS TO")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(copied ? accent : Color.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayed.map(formatAmount) ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    // Nine digits fit at full size; a ten-digit rupiah total shrinks
                    // rather than clipping or widening the panel.
                    .minimumScaleFactor(0.5)
                Spacer()
                Text(to)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text(footnote)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { copyResult() }
        .help("Click to copy")
    }

    private var footnote: String {
        guard let rates, let unit = convert(1, from: from, to: to, rates: rates.rates) else {
            return "fetching rates…"
        }
        return "ECB rate \(shortDate(rates.date))\(offline ? " · offline" : "")"
            + " · 1 \(from) = \(formatRate(unit)) \(to)"
    }

    private func copyResult() {
        guard let displayed else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatAmount(displayed), forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = false }
        }
    }

    // MARK: Rates

    private func loadRates() async {
        let cached = decodeCache()
        if let cached { rates = cached }                       // show something immediately
        if let at = cached?.fetchedAt, Date.now.timeIntervalSince(at) < 3600 { return }

        do {
            let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=EUR")!
            let (data, _) = try await URLSession.shared.data(from: url)
            var fresh = try JSONDecoder().decode(RateSet.self, from: data)
            fresh.rates["EUR"] = 1.0                           // the base is not in the payload
            fresh.fetchedAt = .now
            rates = fresh
            // A currency can leave the ECB list between launches.
            if fresh.rates[from] == nil { from = "USD" }
            if fresh.rates[to] == nil { to = "EUR" }
            offline = false
            if let encoded = try? JSONEncoder().encode(fresh) {
                cachedRates = String(decoding: encoded, as: UTF8.self)
            }
        } catch {
            offline = rates != nil                             // stale rates still convert
        }
    }

    private func decodeCache() -> RateSet? {
        guard !cachedRates.isEmpty else { return nil }
        return try? JSONDecoder().decode(RateSet.self, from: Data(cachedRates.utf8))
    }
}
