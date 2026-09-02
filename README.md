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

Drag PDFs onto the window, or use the file picker. Output is written to
`~/Documents/PDFtoExcel/`.

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
- **`Info.plist` and the entitlements file are not bundled.** SwiftPM reports
  them as unhandled resources, so the built binary does not carry them. Signing
  or distributing the app needs an Xcode target or an explicit `resources:`
  declaration.
- **No automated tests.** Table detection was verified by hand against generated
  fixtures with known contents, covering multi-page documents, two tables on one
  page, blank cells, and simulated scans from zero to six degrees of tilt. Real
  scanner output has been checked for robustness and skew behaviour, but not
  against a scanned document containing a real table.

## Source layout

| File | Role |
| ---- | ---- |
| `PDFtoExcel.swift` | `PDFToExcelConverter` — the default engine |
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
