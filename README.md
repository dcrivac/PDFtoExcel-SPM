# PDFtoExcel

A macOS app that pulls tables out of PDFs — including scans with no text layer —
and writes them to CSV or XLSX. Pages are rasterized and read with Vision OCR, so
a scanned document works the same way a digital one does.

## Requirements

- macOS 26.0 or later
- Swift 5.9 toolchain

## Build and run

```sh
swift build
swift run PDFtoExcel
```

Drag PDFs onto the window, use the file picker, or open a PDF with the app from
Finder.

Output goes to `Documents/PDFtoExcel/`. Which `Documents` that is depends on how
the app is running: `swift run` is unsandboxed and writes to `~/Documents`, while
the signed bundle from `make-app.sh` is sandboxed and writes inside its container
at `~/Library/Containers/com.pdftoexcel.app/Data/Documents/`.

### Building an .app

SwiftPM produces a bare executable rather than an application bundle. To get a
double-clickable, sandboxed app:

```sh
./Scripts/make-app.sh release          # -> build/PDFtoExcel.app
open build/PDFtoExcel.app
```

The script assembles the bundle and applies the entitlements, which can only be
attached when signing. It signs ad-hoc by default; set `CODESIGN_IDENTITY` to
sign with a Developer ID, which also enables the hardened runtime and a secure
timestamp.

`Info.plist` itself is embedded directly into the executable by the linker (see
the `-sectcreate` flags in `Package.swift`), so the bundle identifier and
document types are available even when running the bare binary via `swift run`.

### Tests

```sh
swift test
```

The suite drives the detection heuristics on synthetic OCR output — pages built
cell by cell in `Tests/PDFtoExcelTests/PageFixtures.swift`, where the layout is
known exactly — so row grouping, column alignment, tilt correction and the prose
filter can each be checked on their own. Two tests are marked as known issues:
they assert the behaviour that is wanted and record that it does not hold yet
(see *Known limitations*).

`ScanCorpusTests` reads a real scan end to end through Vision. The corpus is
large and local-only, so those tests skip when `pdf_test_files/` is absent.

## How it works

Every page goes through the same five stages:

1. **Render** — the page is rasterized to an image. Nothing reads the PDF's text
   layer, so scans and digital documents follow one path.
2. **Recognize** — Vision OCR returns text runs with their positions. If the page
   turns out to be tilted more than two degrees, it is straightened and read
   again (see *Deskewing*).
3. **Group into rows** — runs sharing a baseline become a row.
4. **Find columns** — the x positions across a table are clustered, and each run
   is placed in the column it sits under. Blank cells stay blank rather than
   shifting their row.
5. **Split and write** — rows are divided into tables and written out.

### Deskewing

Vision reports an axis-aligned box for most short words, so a page's tilt cannot
be read from any single observation — it only shows up in how observations sit
relative to one another. `TextSkew` tries candidate angles and keeps whichever
packs text into the fewest, densest horizontal bands, since a row only collapses
into one band when the page is level.

A tilt is believed only when it beats reading the page level by a clear margin.
Without that check, multi-column prose produces false positives: a slanted
reading can line one column's rows up against another's and score marginally
best on a page that is perfectly square.

## Two engines

The app ships with two independent conversion pipelines. The default is used
unless **Settings ▸ Performance ▸ Use Optimized Processor** is switched on.

|                | Default (`PDFToExcelConverter`) | Optimized (`OptimizedPDFProcessor`) |
| -------------- | ------------------------------- | ----------------------------------- |
| Output formats | CSV and XLSX                    | **CSV only** — ignores the format setting |
| File suffix    | `_converted`                    | `_optimized`                        |
| Table detection| Built in                        | `EnhancedTableDetector`, three strategies merged and deduplicated |
| Extras         | —                               | Column data-type detection, confidence and type headers |
| Memory         | Whole document                  | Chunked, with a memory-pressure pause between chunks |
| Concurrency    | Three pages of OCR at a time    | Configurable, capped at five        |

Both render pages serially and run OCR concurrently. PDFKit is not documented as
safe for concurrent access to one document, so a page is rasterized on the owning
task and only the finished image — immutable and `Sendable` — crosses into the
OCR tasks.

## Settings

These affect conversion:

| Key                             | Effect |
| ------------------------------- | ------ |
| `settings.outputFormat`         | `csv` or `xlsx` (default engine only) |
| `settings.accuracy`             | Vision recognition level: `fast` or `accurate` |
| `settings.separateByPage`       | Whether pages are written as separate blocks |
| `settings.useOptimizedProcessor`| Selects the optimized engine |

These appear in the Settings window but are **not yet wired to anything**:
`enableLogging`, `maxConcurrentJobs`, `minimumTableSize`, `includeConfidence`,
`outputDirectory`.

## Known limitations

- **The optimized engine always writes CSV.** It never calls `writeXLSX`, so an
  `xlsx` output setting is silently ignored while it is enabled. This is why it
  is opt-in rather than the default.
- **Deskewing corrects a single global tilt per page.** Page curl from a book
  spine, or perspective from a phone camera, is non-uniform and will not be
  corrected by one rotation.
- **OCR is the accuracy floor.** Below roughly 100 dpi the recognizer misreads
  words regardless of what the table logic does; no geometric correction
  recovers text that was never legible.
- **A notarized build needs a Developer ID.** `make-app.sh` signs ad-hoc by
  default, which is fine locally but will be refused by Gatekeeper on another
  Mac. Pass `CODESIGN_IDENTITY` for a real identity; notarizing then also needs
  `xcrun notarytool`, which this repository does not automate.
- **The bordered strategy misplaces cells after a blank.** `EnhancedTableDetector`'s
  bordered reading takes a row's cells in x order and pads the end, so a blank
  cell shifts every value after it one column left. The default engine places
  each cell in the column it sits under; the same fix has not been applied to the
  optimized engine. Covered by a known-issue test.
- **Only dollar amounts are recognized as currency.** The symbol list in
  `DataTypeDetector` was written to the file double-encoded, so it holds mojibake
  rather than `€`, `£` and the rest, and no other currency matches. Covered by a
  known-issue test.
- **`XLSXGenerator` is not wired up.** Both engines write XLSX through
  `ExcelWriter.writeXLSX`, which writes a CSV and renames it; the real workbook
  generator is never called.

## Source layout

| File | Role |
| ---- | ---- |
| `PDFtoExcel.swift` | `PDFToExcelConverter` — the default engine |
| `PageTableParser.swift` | The default engine's page-to-tables parsing |
| `TextRun.swift` | Positioned text, and the boundary with Vision |
| `PerformanceOptimizations.swift` | `OptimizedPDFProcessor` and its cache |
| `TableDetectionEnhancements.swift` | `EnhancedTableDetector`, used by the optimized engine |
| `TextSkew.swift` | Page-tilt estimation |
| `TextRecognition.swift` | Shared OCR entry point, including the levelled re-read |
| `ExcelWriter.swift`, `XLSXGenerator.swift` | CSV and XLSX output |
| `DataTypeDetector.swift` | Column type inference |
| `ContentView.swift`, `SettingsView.swift`, `Processing*.swift` | SwiftUI interface |

## License

MIT — see [LICENSE](LICENSE).

The one dependency, [ZIPFoundation](https://github.com/weichsel/ZIPFoundation),
is MIT as well.
