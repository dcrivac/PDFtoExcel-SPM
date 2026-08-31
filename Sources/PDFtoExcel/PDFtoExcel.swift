//
//  PDFtoExcel.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers
import Combine
import OSLog
import AppKit

// MARK: - PDF to Excel Converter

@MainActor
class PDFToExcelConverter: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var processedFiles: [ProcessedFile] = []
    @Published var selectedFile: ProcessedFile?
    
    nonisolated let logger = Logger(subsystem: "com.pdftoexcel.app", category: "Converter")
    private var cancellables = Set<AnyCancellable>()
    
    /// Alternative engine, used when the "Use Optimized Processor" setting is on.
    private let optimizedProcessor = OptimizedPDFProcessor()
    
    init() {
        // The views observe this object, not the optimized engine, so mirror its
        // per-page progress across while it is the one doing the work.
        optimizedProcessor.$progress
            .sink { [weak self] value in self?.progress = value }
            .store(in: &cancellables)
    }
    
    @AppStorage("settings.outputFormat") private var outputFormatRaw: String = "csv"
    @AppStorage("settings.accuracy") private var accuracyRaw: String = "accurate"
    @AppStorage("settings.separateByPage") private var separateByPage: Bool = true
    @AppStorage("settings.useOptimizedProcessor") private var useOptimizedProcessor: Bool = false
    
    enum OutputFormat: String { case csv, xlsx }
    enum RecognitionAccuracy: String { case fast, accurate }
    
    private var outputFormat: OutputFormat { OutputFormat(rawValue: outputFormatRaw) ?? .csv }
    var recognitionAccuracy: RecognitionAccuracy { RecognitionAccuracy(rawValue: accuracyRaw) ?? .accurate }
    
    // MARK: - Public Methods
    
    func clearProcessedFiles() {
        processedFiles.removeAll()
        selectedFile = nil
    }
    
    func removeProcessedFile(_ file: ProcessedFile) {
        processedFiles.removeAll { $0.id == file.id }
        if selectedFile?.id == file.id {
            selectedFile = nil
        }
        
        // Optionally delete the output file
        try? FileManager.default.removeItem(at: file.outputURL)
    }
    
    func openOutputFile(_ file: ProcessedFile) {
        NSWorkspace.shared.open(file.outputURL)
    }
    
    func revealInFinder(_ file: ProcessedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.outputURL])
    }
    
    func convertFiles(_ urls: [URL]) async {
        isProcessing = true
        progress = 0.0
        
        let totalFiles = urls.count
        
        for (index, url) in urls.enumerated() {
            do {
                let processedFile = try await convertSingleFile(url)
                processedFiles.append(processedFile)
                logger.info("Successfully converted: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to convert \(url.lastPathComponent): \(error.localizedDescription)")
            }
            
            progress = Double(index + 1) / Double(totalFiles)
        }
        
        isProcessing = false
    }
    
    public func convertSingleFile(_ url: URL) async throws -> ProcessedFile {
        if useOptimizedProcessor {
            logger.info("Converting \(url.lastPathComponent) with the optimized processor")
            return try await optimizedProcessor.processSinglePDFOptimized(
                url,
                options: OptimizedPDFProcessor.ProcessingOptions()
            )
        }
        
        // ⚡ TIER 2 OPTIMIZATION: Render serially, then OCR pages in parallel.
        // The document is opened off the main actor and stays there.
        let (allTables, pageCount) = try await processPagesConcurrently(
            at: url,
            accuracy: recognitionAccuracy
        )
        
        // Generate Excel file
        let outputURL = try generateExcelFile(from: allTables, originalURL: url)
        
        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
        
        return ProcessedFile(
            originalURL: url,
            outputURL: outputURL,
            fileName: url.deletingPathExtension().lastPathComponent,
            pageCount: pageCount,
            tablesFound: allTables.count,
            processedDate: Date(),
            fileSize: fileSize
        )
    }
    
    // MARK: - Parallel Page Processing (Tier 2 Optimization)
    
    /// Rasterize each page in turn, then OCR the rendered images concurrently.
    ///
    /// PDFKit is not documented as safe for concurrent access to a single
    /// document, so the `PDFDocument` is opened and read entirely within this
    /// task and never crosses into the child tasks. Only finished `CGImage`s,
    /// which are immutable and `Sendable`, are handed to the OCR tasks.
    ///
    /// - Parameters:
    ///   - url: Location of the PDF to read
    ///   - accuracy: Recognition accuracy, read from settings by the caller
    /// - Returns: All TableData across the document, in page order, and the page count
    private nonisolated func processPagesConcurrently(
        at url: URL,
        accuracy: RecognitionAccuracy
    ) async throws -> (tables: [TableData], pageCount: Int) {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ConversionError.invalidPDFFile
        }
        
        let pageCount = pdfDocument.pageCount
        let maxConcurrentPages = 3  // OCR 3 pages simultaneously
        var allTablesByPage: [Int: [TableData]] = [:]
        var processedPagesCount = 0
        
        logger.info("Starting parallel page processing: \(pageCount) pages, \(maxConcurrentPages) concurrent")
        
        try await withThrowingTaskGroup(of: (pageIndex: Int, tables: [TableData]).self) { group in
            var nextPageToQueue = 0
            
            // Queue initial batch of pages
            for _ in 0..<min(maxConcurrentPages, pageCount) {
                let pageIndex = nextPageToQueue
                let image = renderPage(pdfDocument, at: pageIndex)
                group.addTask {
                    guard let image else { return (pageIndex, []) }
                    
                    self.logger.debug("Processing page \(pageIndex + 1)/\(pageCount)")
                    let tables = try await self.extractTablesFromCGImage(image, pageNumber: pageIndex + 1, accuracy: accuracy)
                    return (pageIndex, tables)
                }
                nextPageToQueue += 1
            }
            
            // Collect results and queue more pages
            for try await result in group {
                allTablesByPage[result.pageIndex] = result.tables
                processedPagesCount += 1
                
                // Update progress
                let fractionComplete = Double(processedPagesCount) / Double(pageCount)
                await MainActor.run { self.progress = fractionComplete }
                
                logger.debug("Completed page \(result.pageIndex + 1), progress: \(String(format: "%.0f%%", fractionComplete * 100))")
                
                // Queue next page if available
                if nextPageToQueue < pageCount {
                    let pageIndex = nextPageToQueue
                    let image = renderPage(pdfDocument, at: pageIndex)
                    group.addTask {
                        guard let image else { return (pageIndex, []) }
                        
                        self.logger.debug("Processing page \(pageIndex + 1)/\(pageCount)")
                        let tables = try await self.extractTablesFromCGImage(image, pageNumber: pageIndex + 1, accuracy: accuracy)
                        return (pageIndex, tables)
                    }
                    nextPageToQueue += 1
                }
            }
        }
        
        // Reconstruct in page order and combine all tables
        var allTables: [TableData] = []
        for pageIndex in 0..<pageCount {
            if let tables = allTablesByPage[pageIndex] {
                allTables.append(contentsOf: tables)
            }
        }
        
        logger.info("Parallel processing complete: found \(allTables.count) tables across \(pageCount) pages")
        return (allTables, pageCount)
    }
    
    /// Rasterize one page for OCR.
    ///
    /// Only ever called from `processPagesConcurrently`'s own task, so PDFKit
    /// sees a single reader of the document.
    private nonisolated func renderPage(_ pdfDocument: PDFDocument, at pageIndex: Int) -> CGImage? {
        guard let page = pdfDocument.page(at: pageIndex) else {
            logger.warning("Could not load page \(pageIndex + 1)")
            return nil
        }
        return renderImage(of: page, pageNumber: pageIndex + 1)
    }
    
    /// Rasterize a page at OCR resolution.
    nonisolated func renderImage(of page: PDFPage, pageNumber: Int) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution for better OCR
        let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.warning("Failed to create thumbnail for page \(pageNumber)")
            return nil
        }
        return cgImage
    }
    
    func extractTablesFromPage(_ page: PDFPage, pageNumber: Int, accuracy: RecognitionAccuracy) async throws -> [TableData] {
        guard let cgImage = renderImage(of: page, pageNumber: pageNumber) else { return [] }
        return try await extractTablesFromCGImage(cgImage, pageNumber: pageNumber, accuracy: accuracy)
    }
    
    /// One OCR'd line: its vertical position and the text runs found on it.
    private struct TextRow {
        var y: CGFloat
        var cells: [(x: CGFloat, text: String)]
    }
    
    private nonisolated func parseTextIntoTables(_ observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        let rows = groupObservationsIntoRows(observations)
        
        return splitRowsIntoTables(rows).compactMap { group -> TableData? in
            // Two rows is the minimum that can establish a repeated structure.
            guard group.count >= 2 else { return nil }
            
            let columns = columnPositions(in: group)
            guard columns.count >= 2 else { return nil }
            
            let tableRows = group.map { alignCells(of: $0, to: columns) }
            
            return TableData(
                rows: tableRows,
                columnCount: columns.count,
                rowCount: tableRows.count,
                confidence: calculateTableConfidence(tableRows),
                pageNumber: pageNumber
            )
        }
    }
    
    /// Collect observations onto shared baselines, top to bottom.
    private nonisolated func groupObservationsIntoRows(_ observations: [VNRecognizedTextObservation]) -> [TextRow] {
        let yTolerance: CGFloat = 0.02
        var rows: [TextRow] = []
        
        // midY rather than the bottom edge: cells on one line differ in height,
        // so their baselines separate further than their centres do.
        for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            
            let y = observation.boundingBox.midY
            let x = observation.boundingBox.minX
            
            if let index = rows.firstIndex(where: { abs($0.y - y) <= yTolerance }) {
                rows[index].cells.append((x: x, text: text))
            } else {
                rows.append(TextRow(y: y, cells: [(x: x, text: text)]))
            }
        }
        
        for index in rows.indices {
            rows[index].cells.sort { $0.x < $1.x }
        }
        return rows
    }
    
    /// Break the page's rows where one table ends and the next begins.
    ///
    /// A row holding a single run is a heading rather than data, so it closes the
    /// table above it and is isolated into a group of its own, which then falls
    /// below the two-row minimum and is dropped. A vertical gap far larger than
    /// the page's usual line spacing separates tables that carry no heading.
    private nonisolated func splitRowsIntoTables(_ rows: [TextRow]) -> [[TextRow]] {
        guard !rows.isEmpty else { return [] }
        
        var spacings: [CGFloat] = []
        for index in 1..<max(rows.count, 1) {
            spacings.append(rows[index - 1].y - rows[index].y)
        }
        let typicalSpacing = spacings.isEmpty ? 0 : spacings.sorted()[spacings.count / 2]
        let spacingLimit = typicalSpacing * 2.5
        
        var groups: [[TextRow]] = []
        var current: [TextRow] = []
        
        for (index, row) in rows.enumerated() {
            let isHeading = row.cells.count == 1
            let brokeVertically = index > 0
                && typicalSpacing > 0
                && (rows[index - 1].y - row.y) > spacingLimit
            
            if isHeading {
                if !current.isEmpty { groups.append(current) }
                groups.append([row])
                current = []
            } else if brokeVertically {
                if !current.isEmpty { groups.append(current) }
                current = [row]
            } else {
                current.append(row)
            }
        }
        
        if !current.isEmpty { groups.append(current) }
        return groups
    }
    
    /// Cluster the x positions occurring in these rows into column references.
    private nonisolated func columnPositions(in rows: [TextRow]) -> [CGFloat] {
        let tolerance: CGFloat = 0.02
        let xs = rows.flatMap { $0.cells.map(\.x) }.sorted()
        guard !xs.isEmpty else { return [] }
        
        var clusters: [[CGFloat]] = [[xs[0]]]
        for x in xs.dropFirst() {
            if let last = clusters[clusters.count - 1].last, x - last <= tolerance {
                clusters[clusters.count - 1].append(x)
            } else {
                clusters.append([x])
            }
        }
        return clusters.map { $0.reduce(0, +) / CGFloat($0.count) }
    }
    
    /// Place each run in the column it sits under, leaving blanks where the
    /// source row has no value.
    ///
    /// Taking the runs in x order and padding the end instead, as this used to,
    /// silently shifts every value left of a blank cell into the wrong column.
    private nonisolated func alignCells(of row: TextRow, to columns: [CGFloat]) -> [String] {
        guard !columns.isEmpty else { return [] }
        var cells = [String](repeating: "", count: columns.count)
        
        for cell in row.cells {
            var bestIndex = 0
            var bestDistance = abs(columns[0] - cell.x)
            for (index, position) in columns.enumerated().dropFirst() {
                let distance = abs(position - cell.x)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            cells[bestIndex] = cells[bestIndex].isEmpty
                ? cell.text
                : cells[bestIndex] + " " + cell.text
        }
        
        return cells
    }
    
    private nonisolated func calculateTableConfidence(_ rows: [[String]]) -> Float {
        guard rows.count >= 2 else { return 0.0 }
        
        let columnCount = rows.first?.count ?? 0
        var consistencyScore: Float = 0.0
        var numericColumnScore: Float = 0.0
        
        // Check column consistency
        let consistentColumns = rows.filter { $0.count == columnCount }.count
        consistencyScore = Float(consistentColumns) / Float(rows.count)
        
        // Check for numeric data (common in tables)
        if columnCount > 0 {
            var numericColumns = 0
            for colIndex in 0..<columnCount {
                let columnValues = rows.compactMap { $0.count > colIndex ? $0[colIndex] : nil }
                let numericValues = columnValues.filter { 
                    Double($0.replacingOccurrences(of: ",", with: "")) != nil 
                }
                
                if Float(numericValues.count) / Float(columnValues.count) > 0.5 {
                    numericColumns += 1
                }
            }
            numericColumnScore = Float(numericColumns) / Float(columnCount)
        }
        
        return (consistencyScore * 0.7) + (numericColumnScore * 0.3)
    }
    
    nonisolated func extractTablesFromCGImage(_ cgImage: CGImage, pageNumber: Int, accuracy: RecognitionAccuracy) async throws -> [TableData] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    self.logger.error("Vision text recognition failed: \(error.localizedDescription)")
                    continuation.resume(throwing: ConversionError.visionProcessingError)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                self.logger.info("Found \(observations.count) text observations on page \(pageNumber)")
                let tables = self.parseTextIntoTables(observations, pageNumber: pageNumber)
                continuation.resume(returning: tables)
            }

            // ⚡ TIER 2: Keep accurate mode but disable language correction for speed
            request.recognitionLevel = (accuracy == .accurate) ? .accurate : .fast
            request.usesLanguageCorrection = false  // Disabled for speed (~10% faster)
            request.recognitionLanguages = ["en-US"]
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                self.logger.error("Failed to perform Vision request: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    func generateExcelFile(from tables: [TableData], originalURL: URL) throws -> URL {
        // Determine output directory (Documents/PDFtoExcel)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = documents.appendingPathComponent("PDFtoExcel", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let baseName = originalURL.deletingPathExtension().lastPathComponent + "_converted"
        let ext = (outputFormat == .csv) ? "csv" : "xlsx"
        var outputURL = outputDir.appendingPathComponent(baseName).appendingPathExtension(ext)
        
        // Avoid overwriting: append (2), (3), ... if needed
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let candidateName = "\(baseName) (\(counter))"
            outputURL = outputDir.appendingPathComponent(candidateName).appendingPathExtension(ext)
            counter += 1
        }
        
        let writer = ExcelWriter()
        if outputFormat == .csv {
            try writer.writeCSV(tables: tables, to: outputURL, separateByPage: separateByPage)
        } else {
            try writer.writeXLSX(tables: tables, to: outputURL, separateByPage: separateByPage)
        }
        
        return outputURL
    }
}

