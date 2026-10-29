# CurrencyPop

A macOS menu bar popover that converts an amount — or a bit of arithmetic —
between currencies. Click the ⇄ icon, type `1250+300*2`, read the number,
click away. No window, no Dock icon, no sign-in, no dependencies.

## Install

Download `CurrencyPop.zip` from the
[latest release](https://github.com/dinhthaidaica/CurrencyPop/releases/latest),
unzip it and drag `CurrencyPop.app` to `/Applications`. Releases are signed
and notarised, so it opens with a double-click.

It has no Dock icon and no window. Look for the ⇄ in your menu bar.

To have it start with your Mac: System Settings → General → Login Items →
**+** → CurrencyPop.

## Build

```sh
./build.sh        # builds CurrencyPop.app next to the script
./build.sh run    # builds, then launches it
./build.sh test   # runs the arithmetic, conversion and decoding checks
```

Requires Xcode command line tools. There is no Xcode project: `build.sh`
compiles the two Swift files with `swiftc` and assembles the `.app` bundle
by hand, which is the whole reason the source stays this small.

## How it works

- **Rates** come from [frankfurter.dev](https://frankfurter.dev), which serves
  European Central Bank reference rates. No API key. One fetch of the
  EUR-based table covers every pair by cross rate, refreshed hourly and
  cached in `UserDefaults`, so switching currencies never waits on the
  network and stale rates still convert when offline.
- **Arithmetic** in the amount field is evaluated by `NSExpression`, guarded
  by a regex that only admits a complete flat expression. That guard is not
  cosmetic: `NSExpression` raises an Objective-C exception on malformed
  input that Swift cannot catch, and a field being typed into is malformed
  on most keystrokes.
- **Precision** follows the currency, not the size of the number: cents on
  USD and øre on DKK at any magnitude, none on VND or JPY, which have no
  minor unit. ECB rates themselves update once per working day — good for
  travel math and invoices, not for trading.
- **Updates** are checked once a day against this repository's releases
  page. When a newer tag exists the panel shows a line offering the
  download; it never installs anything on its own. That daily request to
  `api.github.com` is the only network traffic besides the rate fetch.

## Files

| File | What it holds |
| --- | --- |
| `Math.swift` | Expression evaluation, cross-rate conversion, formatting, the rate model. No UI imports, so the checks can run against it. |
| `CurrencyPop.swift` | `MenuBarExtra` scene and the panel. |
| `tests/main.swift` | 26 assertions, run with `./build.sh test`. |
| `build.sh` | Compile, assemble the bundle, ad-hoc sign. |
| `release.sh` | Sign with a Developer ID, notarise, staple, publish a GitHub release. |
| `tools/makeicon.swift` | Regenerates `CurrencyPop.icns`. Only needed if the mark changes. |
| `docs/plan.html` | The design and build plan this was written from. |

## Releasing

```sh
./release.sh v1.0
```

Needs a Developer ID Application certificate in your keychain and a stored
`notarytool` credential profile; `release.sh` explains both at the top and
refuses to start without the certificate.

## Deliberately left out

Parentheses and `%` in the field, crypto, rate history, favourites, a
preferences window, launch at login. Each has a trigger for adding it in
`docs/plan.html`.

## License

MIT. See [LICENSE](LICENSE).
