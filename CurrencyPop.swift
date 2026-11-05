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
    // Seeded from the keys the single-pair version wrote, so an upgrade opens
    // on the same pair. They are left in place; nothing reads them after this.
    @AppStorage("conversions") private var rows = [Conversion(
        input: UserDefaults.standard.string(forKey: "input") ?? "100",
        from: UserDefaults.standard.string(forKey: "from") ?? "USD",
        to: UserDefaults.standard.string(forKey: "to") ?? "EUR")]
    @AppStorage("cachedRates") private var cachedRates = ""
    @AppStorage("lastUpdateCheck") private var lastUpdateCheck = 0.0
    @AppStorage("latestTag") private var latestTag = ""
    @AppStorage("latestURL") private var latestURL = ""

    @State private var rates: RateSet?
    @State private var offline = false
    @FocusState private var focused: UUID?
    // ⌘S and ⇧⌘C stay here when focus leaves the fields; only the amount fields move it,
    // so tabbing onto another row's picker leaves them on the last row typed in.
    @State private var lastFocused: UUID?
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($rows) { $row in
                            // One view per id, so scrollTo lands on the row, not its divider.
                            VStack(alignment: .leading, spacing: 10) {
                                if row.id != rows[0].id { Divider() }
                                ConversionRow(
                                    conversion: $row, rates: rates, focused: $focused,
                                    hasShortcuts: row.id == (rows.first { $0.id == lastFocused }?.id ?? rows[0].id),
                                    remove: rows.count > 1 ? { [id = row.id] in removeRow(id) } : nil)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                // A fixed height, not just a cap: the menu bar panel sizes itself from
                // the smallest height its content accepts, and a bare ScrollView
                // accepts zero, which hid every row. Past the smallest screen's height
                // the rows scroll; the margin keeps the bottom bar and the update
                // notice on screen. Smallest, because NSScreen.main follows the key
                // window, which may be on another display.
                .frame(height: min(rowsHeight, (NSScreen.screens.map(\.visibleFrame.height).min() ?? 800) - 140))
                .onChange(of: rows.count) { old, new in
                    if new > old, let id = rows.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            bottomBar
            if let update { updateNotice(update) }
        }
        .padding(14)
        .frame(width: 340)
        .tint(accent)
        .onChange(of: focused) { _, new in if let new { lastFocused = new } }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = rows[0].id }
        }
        .task {
            await loadRates()
            await checkForUpdate()
        }
    }

    // MARK: Rows

    private var bottomBar: some View {
        HStack {
            Button(action: addRow) {
                Label("Add conversion", systemImage: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("Add a conversion (⌘N)")
            Spacer()
            Text(footer)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .help("ECB rates via frankfurter.dev; VND from fawazahmed0's currency-api")
        }
    }

    /// Once for the whole panel: every row converts with the same table.
    private var footer: String {
        guard let rates else { return "" }
        let source: String
        if let vndDate = rates.vndDate, rows.contains(where: { $0.from == "VND" || $0.to == "VND" }) {
            // Kept short; the tooltip names the source.
            source = "ECB \(shortDate(rates.date)) · VND \(shortDate(vndDate))"
        } else {
            source = "ECB rate \(shortDate(rates.date))"
        }
        return source + (offline ? " · offline" : "")
    }

    /// A new row starts on the last row's pair, the likeliest one to want again.
    private func addRow() {
        let new = Conversion(from: rows[rows.count - 1].from, to: rows[rows.count - 1].to)
        rows.append(new)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = new.id }
    }

    /// Focus moves only if it was on the removed row: to the row that takes its
    /// place, or the one above when it was the last. A turn later, because
    /// moving it in the same update re-renders the removed row past the end.
    private func removeRow(_ id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: i)
        if focused == id { DispatchQueue.main.async { focused = rows[min(i, rows.count - 1)].id } }
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
        // ponytail: the VND check only bites until currency-api has answered once;
        // after that a cache with VND in it waits out the hour like any other.
        // If it never answers, every open refetches both; the cache still shows first.
        if let at = cached?.fetchedAt, Date.now.timeIntervalSince(at) < 3600,
           cached?.rates["VND"] != nil { return }

        do {
            async let vnd = fetchVND()
            let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=EUR")!
            let (data, _) = try await URLSession.shared.data(from: url)
            var fresh = try JSONDecoder().decode(RateSet.self, from: data)
            fresh.rates["EUR"] = 1.0                           // the base is not in the payload
            fresh.addVND(await vnd, keeping: cached)
            fresh.fetchedAt = .now
            rates = fresh
            // A currency can leave the ECB list between launches.
            for i in rows.indices {
                if fresh.rates[rows[i].from] == nil { rows[i].from = "USD" }
                if fresh.rates[rows[i].to] == nil { rows[i].to = "EUR" }
            }
            offline = false
            if let encoded = try? JSONEncoder().encode(fresh) {
                cachedRates = String(decoding: encoded, as: UTF8.self)
            }
        } catch {
            offline = rates != nil                             // stale rates still convert
        }
    }

    /// The one rate the ECB table lacks. nil on any failure; the merge then keeps the cached one.
    private func fetchVND() async -> VNDQuote? {
        let url = URL(string: "https://latest.currency-api.pages.dev/v1/currencies/eur.json")!
        // 5s idle, not the default 60: the ECB rates wait on this before they reach the screen.
        guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5))
        else { return nil }
        return try? JSONDecoder().decode(VNDQuote.self, from: data)
    }

    private func decodeCache() -> RateSet? {
        guard !cachedRates.isEmpty else { return nil }
        return try? JSONDecoder().decode(RateSet.self, from: Data(cachedRates.utf8))
    }
}

// MARK: - Row

/// One conversion: amount, pair, result. The panel stacks as many as you add.
struct ConversionRow: View {
    @Binding var conversion: Conversion
    let rates: RateSet?
    var focused: FocusState<UUID?>.Binding
    let hasShortcuts: Bool                   // one row at a time, not every row at once
    let remove: (() -> Void)?                // nil for the only row, so it has no ×

    @State private var displayed: Double?   // last good result, kept while you retype
    @State private var swapAngle = 0.0
    @State private var copied = false

    /// nil while the expression is half-typed.
    private var amount: Double? { evaluate(conversion.input) }

    private var result: Double? {
        guard let amount, let rates else { return nil }
        return convert(amount, from: conversion.from, to: conversion.to, rates: rates.rates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            amountLabel
            amountField
            pickerRow
            resultBlock
        }
        .onChange(of: result) { _, new in if let new { displayed = new } }
        .onAppear { displayed = result }
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
            if let remove {
                Button(action: remove) {
                    Label("Remove conversion", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(conversion.from) to \(conversion.to)")
                .help("Remove this conversion")
            }
        }
    }

    /// The running total, shown when the field holds more than a plain number:
    /// an operator, or a "." or "," whose reading ("1.250" as 1250 or 1.25)
    /// should be visible rather than guessed silently.
    @State private var lastSubtotal: String?
    private var subtotal: String? {
        guard conversion.input.contains(where: { "+-*/.,".contains($0) }) else { return nil }
        guard let amount else { return lastSubtotal }
        return formatAmount(amount, conversion.from)
    }

    private var amountField: some View {
        HStack(spacing: 8) {
            TextField("", text: $conversion.input)
                .textFieldStyle(.plain)
                .font(.system(size: 24, design: .monospaced))
                .focused(focused, equals: conversion.id)
                .onChange(of: conversion.input) { _, _ in lastSubtotal = subtotal }
            Text(conversion.from)
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
                picker("From", $conversion.from)
                picker("To", $conversion.to)
            }
            Button(action: swap) {
                Label("Swap currencies", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(accent.opacity(0.14)))
                    .rotationEffect(.degrees(swapAngle))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(hasShortcuts ? KeyboardShortcut("s", modifiers: .command) : nil)
            .help("Swap currencies (⌘S)")
        }
    }

    /// Whatever today's rate table actually holds; the static list only covers
    /// the moments before the first fetch answers.
    private var available: [String] {
        rates.map { $0.rates.keys.sorted() } ?? fallbackCurrencies
    }

    private func picker(_ title: String, _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(available, id: \.self) { code in
                Text("\(code)   \(currencyName(code))").tag(code)
            }
        }
        .labelsHidden()
    }

    private func swap() {
        (conversion.from, conversion.to) = (conversion.to, conversion.from)
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
                Text(displayed.map { formatAmount($0, conversion.to) } ?? "—")
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    // Nothing shares this line but the currency code, so eleven
                    // digits of rupiah fit before the scale factor has to bite.
                    .minimumScaleFactor(0.5)
                Text(conversion.to)
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
        // ⌘C stays with the field
        .keyboardShortcut(hasShortcuts ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        .help("Copy the converted amount (⇧⌘C)")
    }

    /// The ECB date, the VND date and the offline mark sit once in the panel's bottom bar.
    private var footnote: String {
        guard let rates, let unit = convert(1, from: conversion.from, to: conversion.to,
                                            rates: rates.rates) else {
            return "fetching rates…"
        }
        return "1 \(conversion.from) = \(formatRate(unit)) \(conversion.to)"
    }

    private func copyResult() {
        guard let displayed else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatAmount(displayed, conversion.to), forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = false }
        }
    }
}
