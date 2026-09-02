//
//  PerformanceOptimizations.swift
//  PDFtoExcel
//
//  Memory management and parallel processing optimizations
//  Created by Assistant on 11/07/25.
//

import Foundation
import PDFKit
import Vision
import OSLog
import Combine

// MARK: - Optimized PDF Processor

@MainActor
class OptimizedPDFProcessor: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var currentOperation: String = ""
    @Published var memoryUsage: String = "0 MB"
    
    private nonisolated let logger = Logger(subsystem: "com.pdftoexcel.app", category: "OptimizedProcessor")
    private nonisolated let tableDetector = EnhancedTableDetector()
    
    struct ProcessingOptions {
        var maxConcurrentPages: Int = ProcessInfo.processInfo.activeProcessorCount
        var chunkSize: Int = 10  // Pages per chunk
        var maxMemoryMB: Int = 500
        var enableCaching: Bool = true
        var imageScale: CGFloat = 2.5  // Better quality than 2.0
        var useHighQualityOCR: Bool = true
        var enableParallelProcessing: Bool = true
    }
    
    // MARK: - Memory-Optimized Batch Processing
    
    func processPDFBatch(_ urls: [URL], options: ProcessingOptions = ProcessingOptions()) async throws -> [ProcessedFile] {
        var results: [ProcessedFile] = []
        let totalFiles = urls.count
        
        logger.info("Starting batch processing of \(totalFiles) files with optimizations")
        
        for (index, url) in urls.enumerated() {
            // Files are processed one at a time so peak memory stays bounded
            // and the pressure check below can actually pace the loop.
            do {
                let result = try await processSinglePDFOptimized(url, options: options)
                results.append(result)
                
                progress = Double(index + 1) / Double(totalFiles)
                updateMemoryUsage()
            } catch {
                logger.error("Failed to process \(url.lastPathComponent): \(error)")
            }
            
            // Check memory pressure
            if shouldPauseForMemory() {
                logger.info("Pausing for memory pressure")
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
        
        return results
    }
    
    // MARK: - Single PDF Processing with Chunking
    
    nonisolated func processSinglePDFOptimized(_ url: URL, options: ProcessingOptions) async throws -> ProcessedFile {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ConversionError.invalidPDFFile
        }
        
        let pageCount = pdfDocument.pageCount
        var allTables: [TableData] = []
        
        await MainActor.run {
            self.currentOperation = "Processing \(url.lastPathComponent)"
        }
        
        // Process in chunks to manage memory
        for chunkStart in stride(from: 0, to: pageCount, by: options.chunkSize) {
            let chunkEnd = min(chunkStart + options.chunkSize, pageCount)
            
            // Process this chunk separately to avoid memory accumulation
            let chunkTables = try await processChunk(
                pdfDocument: pdfDocument,
                startPage: chunkStart,
                endPage: chunkEnd,
                options: options
            )
            allTables.append(contentsOf: chunkTables)
            
            // Update progress
            await MainActor.run {
                self.progress = Double(chunkEnd) / Double(pageCount)
                self.updateMemoryUsage()
            }
            
            // Allow system to reclaim memory between chunks
            if chunkEnd < pageCount {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        // Generate output with data type detection
        let outputURL = try await generateOptimizedExcelFile(from: allTables, originalURL: url)
        
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
    
    // MARK: - Parallel Chunk Processing
    
    /// Rasterize pages in turn, then OCR the rendered images concurrently.
    ///
    /// PDFKit is not documented as safe for concurrent access to a single
    /// document, so pages are rendered on this task and only the resulting
    /// `CGImage`s -- immutable and `Sendable` -- are handed to the OCR tasks.
    ///
    /// Rendering happens as each slot frees up rather than all at once, so at
    /// most `maxConcurrentPages` page images are resident at a time.
    private nonisolated func processChunk(
        pdfDocument: PDFDocument,
        startPage: Int,
        endPage: Int,
        options: ProcessingOptions
    ) async throws -> [TableData] {
        
        if options.enableParallelProcessing {
            let maxConcurrent = max(1, min(options.maxConcurrentPages, 5))
            
            return try await withThrowingTaskGroup(of: (pageIndex: Int, tables: [TableData]).self) { group in
                var nextPageToQueue = startPage
                // Tasks finish out of order, so results are keyed by page and
                // reassembled below rather than appended as they arrive.
                var tablesByPage: [Int: [TableData]] = [:]
                
                // Fill the window
                while nextPageToQueue < endPage && nextPageToQueue - startPage < maxConcurrent {
                    let pageIndex = nextPageToQueue
                    let image = renderPageImage(pdfDocument, at: pageIndex, scale: options.imageScale)
                    group.addTask { [weak self] in
                        guard let self, let image else { return (pageIndex, []) }
                        return (pageIndex, try await self.extractTables(from: image, pageNumber: pageIndex + 1, options: options))
                    }
                    nextPageToQueue += 1
                }
                
                // Replace each finished page with the next one
                for try await result in group {
                    tablesByPage[result.pageIndex] = result.tables
                    
                    if nextPageToQueue < endPage {
                        let pageIndex = nextPageToQueue
                        let image = renderPageImage(pdfDocument, at: pageIndex, scale: options.imageScale)
                        group.addTask { [weak self] in
                            guard let self, let image else { return (pageIndex, []) }
                            return (pageIndex, try await self.extractTables(from: image, pageNumber: pageIndex + 1, options: options))
                        }
                        nextPageToQueue += 1
                    }
                }
                
                // Reassemble in page order
                var allTables: [TableData] = []
                for pageIndex in startPage..<endPage {
                    if let tables = tablesByPage[pageIndex] {
                        allTables.append(contentsOf: tables)
                    }
                }
                return allTables
            }
        } else {
            // Sequential processing
            var tables: [TableData] = []
            
            for pageIndex in startPage..<endPage {
                guard let image = renderPageImage(pdfDocument, at: pageIndex, scale: options.imageScale) else { continue }
                
                let pageTables = try await extractTables(
                    from: image,
                    pageNumber: pageIndex + 1,
                    options: options
                )
                tables.append(contentsOf: pageTables)
            }
            
            return tables
        }
    }
    
    // MARK: - Optimized Page Processing
    
    /// Rasterize one page for OCR.
    ///
    /// Only ever called from `processChunk`'s own task, so PDFKit sees a single
    /// reader of the document.
    private nonisolated func renderPageImage(_ pdfDocument: PDFDocument, at pageIndex: Int, scale: CGFloat) -> CGImage? {
        autoreleasepool {
            guard let page = pdfDocument.page(at: pageIndex) else { return nil }
            
            let pageRect = page.bounds(for: .mediaBox)
            let thumbnailSize = CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            )
            
            let image = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
    
    private nonisolated func extractTables(
        from cgImage: CGImage,
        pageNumber: Int,
        options: ProcessingOptions
    ) async throws -> [TableData] {
        
        let observations = try TextRecognition.observations(in: cgImage) { request in
            // Configure for best quality
            request.recognitionLevel = options.useHighQualityOCR ? .accurate : .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "es-ES", "fr-FR", "de-DE", "zh-Hans"]
            
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            
            // Set minimum confidence
            request.minimumTextHeight = 0.01  // Detect smaller text
        }
        
        // Use enhanced table detection
        return tableDetector.detectTables(from: observations, pageNumber: pageNumber)
    }
    
    // MARK: - Memory Management
    
    private nonisolated func shouldPauseForMemory() -> Bool {
        // Get current memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return false }
        
        let usedMemoryMB = Int(info.resident_size / 1024 / 1024)
        
        // Pause if using more than 500MB
        return usedMemoryMB > 500
    }
    
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return }
        
        let usedMemoryMB = Int(info.resident_size / 1024 / 1024)
        memoryUsage = "\(usedMemoryMB) MB"
    }
    
    // MARK: - Optimized Excel Generation
    
    private nonisolated func generateOptimizedExcelFile(from tables: [TableData], originalURL: URL) async throws -> URL {
        // Use data type detection for better formatting
        let detector = DataTypeDetector()
        
        var enhancedTables: [(table: TableData, types: [DetectedDataType])] = []
        
        for table in tables {
            let types = detector.detectColumnTypes(table: table)
            enhancedTables.append((table, types))
        }
        
        // Generate with enhanced formatting
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = documents.appendingPathComponent("PDFtoExcel", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let baseName = originalURL.deletingPathExtension().lastPathComponent + "_optimized"
        var outputURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("csv")
        
        // Avoid overwriting
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let candidateName = "\(baseName) (\(counter))"
            outputURL = outputDir.appendingPathComponent(candidateName).appendingPathExtension("csv")
            counter += 1
        }
        
        // Write enhanced CSV with type information
        try await writeEnhancedCSV(enhancedTables, to: outputURL)
        
        return outputURL
    }
    
    private nonisolated func writeEnhancedCSV(_ enhancedTables: [(table: TableData, types: [DetectedDataType])], to url: URL) async throws {
        var csvContent = ""
        csvContent += "# Generated with Enhanced PDF to Excel Converter\n"
        csvContent += "# Confidence scores and data types detected\n\n"
        
        for (index, (table, types)) in enhancedTables.enumerated() {
            if index > 0 {
                csvContent += "\n\n"
            }
            
            // Add metadata
            csvContent += "# Page \(table.pageNumber), Confidence: \(String(format: "%.1f%%", table.confidence * 100))\n"
            
            // Add type information
            let typeNames = types.map { $0.rawValue }.joined(separator: ",")
            csvContent += "# Types: \(typeNames)\n"
            
            // Add header detection
            let analyzer = TableStructureAnalyzer()
            let headerInfo = analyzer.detectHeaders(in: table)
            if headerInfo.hasHeader {
                csvContent += "# Header row detected at index \(headerInfo.headerRow)\n"
            }
            
            // Write actual data
            for row in table.enhancedCleanedRows {
                let escapedRow = row.map { escapeCSVCell($0) }
                csvContent += escapedRow.joined(separator: ",") + "\n"
            }
        }
        
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private nonisolated func escapeCSVCell(_ cell: String) -> String {
        if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
            return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return cell
    }
}

// MARK: - Cache Manager for Performance

/// - Note: `@unchecked` because `NSCache` carries no `Sendable` annotation
///   despite being documented as safe to read and mutate from any thread.
///   Every other stored property is an immutable `Sendable` value, and all
///   file access goes through `FileManager.default`, whose thread-safety
///   guarantee applies to that shared instance specifically.
final class TableDetectionCache: @unchecked Sendable {
    static let shared = TableDetectionCache()
    
    private let cache = NSCache<NSString, CachedTableData>()
    private let cacheDirectory: URL
    
    init() {
        // Set up disk cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("PDFtoExcel/TableCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure memory cache
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB
        cache.countLimit = 100  // Maximum 100 cached pages
    }
    
    func getCachedTables(for pageHash: String) -> [TableData]? {
        // Check memory cache first
        if let cached = cache.object(forKey: pageHash as NSString) {
            return cached.tables
        }
        
        // Check disk cache
        let diskURL = cacheDirectory.appendingPathComponent("\(pageHash).cache")
        if FileManager.default.fileExists(atPath: diskURL.path) {
            if let data = try? Data(contentsOf: diskURL),
               let cached = try? JSONDecoder().decode(CachedTableData.self, from: data) {
                // Promote to memory cache
                cache.setObject(cached, forKey: pageHash as NSString, cost: data.count)
                return cached.tables
            }
        }
        
        return nil
    }
    
    func cacheTables(_ tables: [TableData], for pageHash: String) {
        let cached = CachedTableData(tables: tables, timestamp: Date())
        
        // Store in memory cache
        cache.setObject(cached, forKey: pageHash as NSString, cost: 1024)
        
        // Store on disk asynchronously
        Task {
            let diskURL = cacheDirectory.appendingPathComponent("\(pageHash).cache")
            if let data = try? JSONEncoder().encode(cached) {
                try? data.write(to: diskURL)
            }
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

final class CachedTableData: NSObject, Codable, Sendable {
    let tables: [TableData]
    let timestamp: Date
    
    init(tables: [TableData], timestamp: Date) {
        self.tables = tables
        self.timestamp = timestamp
    }
}

// TableData's Codable conformance is declared in DataModels.swift.
