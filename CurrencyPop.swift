import SwiftUI
import AppKit

// MARK: - Model

let currentVersion = Bundle.main
    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

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
    @AppStorage("lastUpdateCheck") private var lastUpdateCheck = 0.0
    @AppStorage("latestTag") private var latestTag = ""
    @AppStorage("latestURL") private var latestURL = ""

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
            if let update { updateNotice(update) }
        }
        .padding(14)
        .frame(width: 340)
        .tint(accent)
        .onChange(of: result) { _, new in if let new { displayed = new } }
        .onAppear {
            displayed = result
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { amountFocused = true }
        }
        .task {
            await loadRates()
            await checkForUpdate()
        }
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
        guard input.contains(where: { "+-*/".contains($0) }) else { return nil }
        guard let amount else { return lastSubtotal }
        return formatAmount(amount, from)
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayed.map { formatAmount($0, to) } ?? "—")
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    // Nothing shares this line but the currency code, so eleven
                    // digits of rupiah fit before the scale factor has to bite.
                    .minimumScaleFactor(0.5)
                Text(to)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(footnote)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                copyButton
            }
            .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { copyResult() }
    }

    private var copyButton: some View {
        Button(action: copyResult) {
            // Text(Image:) rather than Image: the symbol then carries a text
            // baseline, so it lines up with the result instead of the row's bottom.
            Text(Image(systemName: copied ? "checkmark" : "doc.on.doc"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? accent : Color.secondary)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(displayed == nil)
        .keyboardShortcut("c", modifiers: [.command, .shift])  // ⌘C stays with the field
        .help("Copy the converted amount (⇧⌘C)")
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
        NSPasteboard.general.setString(formatAmount(displayed, to), forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = false }
        }
    }

    // MARK: Updates

    /// Read from what the last check stored, so the notice is on screen the
    /// instant the panel opens rather than a second later. It disappears by
    /// itself once the running version catches up with the tag.
    private var update: (tag: String, url: URL)? {
        guard isNewer(latestTag, than: currentVersion),
              let url = URL(string: latestURL) else { return nil }
        return (latestTag, url)
    }

    private func updateNotice(_ update: (tag: String, url: URL)) -> some View {
        Link(destination: update.url) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle")
                Text("\(update.tag) available")
                Spacer(minLength: 0)
                Text("Download").underline()
            }
            .font(.system(size: 11))
            .foregroundStyle(accent)
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func checkForUpdate() async {
        guard Date.now.timeIntervalSince1970 - lastUpdateCheck > 86_400 else { return }
        let url = URL(string: "https://api.github.com/repos/dinhthaidaica/CurrencyPop/releases/latest")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else { return }
        // Only on success, so a failed check retries on the next open instead
        // of going quiet for a day.
        lastUpdateCheck = Date.now.timeIntervalSince1970
        latestTag = release.tagName
        latestURL = release.htmlUrl
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
