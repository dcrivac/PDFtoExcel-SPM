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
    
    
    nonisolated func extractTablesFromCGImage(_ cgImage: CGImage, pageNumber: Int, accuracy: RecognitionAccuracy) async throws -> [TableData] {
        let observations = try TextRecognition.observations(in: cgImage) { request in
            // ⚡ TIER 2: Keep accurate mode but disable language correction for speed
            request.recognitionLevel = (accuracy == .accurate) ? .accurate : .fast
            request.usesLanguageCorrection = false  // Disabled for speed (~10% faster)
            request.recognitionLanguages = ["en-US"]
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
        }
        
        logger.info("Found \(observations.count) text observations on page \(pageNumber)")
        return PageTableParser().tables(from: TextRun.runs(from: observations), pageNumber: pageNumber)
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

