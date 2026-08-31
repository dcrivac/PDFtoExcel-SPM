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
    
    @AppStorage("settings.outputFormat") private var outputFormatRaw: String = "csv"
    @AppStorage("settings.accuracy") private var accuracyRaw: String = "accurate"
    @AppStorage("settings.separateByPage") private var separateByPage: Bool = true
    
    enum OutputFormat: String { case csv, xlsx }
    enum RecognitionAccuracy: String { case fast, accurate }
    
    private var outputFormat: OutputFormat { OutputFormat(rawValue: outputFormatRaw) ?? .csv }
    private var recognitionAccuracy: RecognitionAccuracy { RecognitionAccuracy(rawValue: accuracyRaw) ?? .accurate }
    
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
        // Load PDF document
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ConversionError.invalidPDFFile
        }
        
        let pageCount = pdfDocument.pageCount
        
        // ⚡ TIER 2 OPTIMIZATION: Process pages in parallel (3-4 concurrent)
        let allTables = try await processPagesConcurrently(pdfDocument, pageCount: pageCount)
        
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
    
    /// Process multiple PDF pages concurrently for faster conversion
    /// - Parameters:
    ///   - pdfDocument: The loaded PDF document
    ///   - pageCount: Total number of pages
    /// - Returns: Array of all TableData from all pages, sorted by page number
    private func processPagesConcurrently(_ pdfDocument: PDFDocument, pageCount: Int) async throws -> [TableData] {
        let maxConcurrentPages = 3  // Process 3 pages simultaneously
        // Read once here, on the main actor, so the page work below can take it
        // as a plain value instead of reaching back for main-actor state.
        let accuracy = recognitionAccuracy
        var allTablesByPage: [Int: [TableData]] = [:]
        var processedPagesCount = 0
        
        logger.info("Starting parallel page processing: \(pageCount) pages, \(maxConcurrentPages) concurrent")
        
        // Use TaskGroup for concurrent processing
        try await withThrowingTaskGroup(of: (pageIndex: Int, tables: [TableData]).self) { group in
            var nextPageToQueue = 0
            
            // Queue initial batch of pages
            for _ in 0..<min(maxConcurrentPages, pageCount) {
                let pageIndex = nextPageToQueue
                group.addTask {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        return (pageIndex, [])
                    }
                    
                    self.logger.debug("Processing page \(pageIndex + 1)/\(pageCount)")
                    let tables = try await self.extractTablesFromPage(page, pageNumber: pageIndex + 1, accuracy: accuracy)
                    return (pageIndex, tables)
                }
                nextPageToQueue += 1
            }
            
            // Collect results and queue more pages
            for try await result in group {
                allTablesByPage[result.pageIndex] = result.tables
                processedPagesCount += 1
                
                // Update progress
                progress = Double(processedPagesCount) / Double(pageCount)
                
                self.logger.debug("Completed page \(result.pageIndex + 1), progress: \(String(format: "%.0f%%", self.progress * 100))")
                
                // Queue next page if available
                if nextPageToQueue < pageCount {
                    let pageIndex = nextPageToQueue
                    group.addTask {
                        guard let page = pdfDocument.page(at: pageIndex) else {
                            return (pageIndex, [])
                        }
                        
                        self.logger.debug("Processing page \(pageIndex + 1)/\(pageCount)")
                        let tables = try await self.extractTablesFromPage(page, pageNumber: pageIndex + 1, accuracy: accuracy)
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
        return allTables
    }
    
    nonisolated func extractTablesFromPage(_ page: PDFPage, pageNumber: Int, accuracy: RecognitionAccuracy) async throws -> [TableData] {
        // Get page bounds and create appropriate thumbnail
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution for better OCR
        let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.warning("Failed to create thumbnail for page \(pageNumber)")
            return []
        }
        
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
            
            // Configure text recognition request
            // ⚡ TIER 2: Keep accurate mode but disable language correction for speed
            request.recognitionLevel = (accuracy == .accurate) ? .accurate : .fast
            request.usesLanguageCorrection = false  // Disabled for speed (~10% faster)
            request.recognitionLanguages = ["en-US"] // Add more languages as needed
            
            // Enable automatic language detection if available
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
    
    private nonisolated func parseTextIntoTables(_ observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        // Sort observations by Y coordinate (top to bottom) then X coordinate (left to right)
        let sortedObservations = observations.sorted { obs1, obs2 in
            let y1 = obs1.boundingBox.origin.y
            let y2 = obs2.boundingBox.origin.y
            
            if abs(y1 - y2) > 0.02 {
                return y1 > y2 // Higher Y means earlier in document
            } else {
                return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x // Left to right
            }
        }
        
        // Group text into rows based on Y coordinates
        var textRows: [(y: CGFloat, texts: [(x: CGFloat, text: String)])] = []
        let yTolerance: CGFloat = 0.02
        
        for observation in sortedObservations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let y = observation.boundingBox.origin.y
            let x = observation.boundingBox.origin.x
            let text = topCandidate.string.trimmingCharacters(in: .whitespaces)
            
            // Skip empty text
            guard !text.isEmpty else { continue }
            
            // Find existing row with similar Y coordinate
            if let existingRowIndex = textRows.firstIndex(where: { abs($0.y - y) <= yTolerance }) {
                textRows[existingRowIndex].texts.append((x: x, text: text))
            } else {
                textRows.append((y: y, texts: [(x: x, text: text)]))
            }
        }
        
        // Sort each row's text by X coordinate and convert to table rows
        var tableRows: [[String]] = []
        for textRow in textRows {
            let sortedTexts = textRow.texts.sorted { $0.x < $1.x }
            let rowData = sortedTexts.map { $0.text }
            
            // Only include rows with multiple columns or substantial content
            if rowData.count > 1 || (rowData.count == 1 && rowData[0].count > 10) {
                tableRows.append(rowData)
            }
        }
        
        // Filter and validate table structure
        let validTables = identifyTableStructures(from: tableRows)
        
        return validTables.map { tableRows in
            let maxColumns = tableRows.map { $0.count }.max() ?? 0
            
            // Normalize rows to have the same number of columns
            let normalizedRows = tableRows.map { row in
                var normalizedRow = row
                while normalizedRow.count < maxColumns {
                    normalizedRow.append("")
                }
                return normalizedRow
            }
            
            return TableData(
                rows: normalizedRows,
                columnCount: maxColumns,
                rowCount: normalizedRows.count,
                confidence: calculateTableConfidence(normalizedRows),
                pageNumber: pageNumber
            )
        }
    }
    
    private nonisolated func identifyTableStructures(from rows: [[String]]) -> [[[String]]] {
        guard rows.count >= 2 else { return [] }
        
        var tables: [[[String]]] = []
        var currentTable: [[String]] = []
        var expectedColumnCount = 0
        
        for row in rows {
            let columnCount = row.count
            
            // Start new table if column structure changes significantly
            if currentTable.isEmpty {
                currentTable = [row]
                expectedColumnCount = columnCount
            } else if abs(columnCount - expectedColumnCount) <= 1 {
                // Accept rows with similar column counts (allow Â±1 variance)
                currentTable.append(row)
            } else {
                // Column structure changed significantly, start new table
                if currentTable.count >= 2 {
                    tables.append(currentTable)
                }
                currentTable = [row]
                expectedColumnCount = columnCount
            }
        }
        
        // Add final table if it has enough rows
        if currentTable.count >= 2 {
            tables.append(currentTable)
        }
        
        return tables
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
    
    func extractTablesFromCGImage(_ cgImage: CGImage, pageNumber: Int) async throws -> [TableData] {
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
            request.recognitionLevel = (self.recognitionAccuracy == .accurate) ? .accurate : .fast
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

