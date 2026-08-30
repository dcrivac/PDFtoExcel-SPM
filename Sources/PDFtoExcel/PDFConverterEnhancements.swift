//
//  PDFConverterEnhancements.swift
//  PDFtoExcel
//
//  Performance and error handling enhancements for PDF conversion
//  Created by David Kenji Crivac on 10/16/25.
//

import Foundation
import PDFKit
import Vision
import OSLog
import Darwin
import UniformTypeIdentifiers

// MARK: - Enhanced Error Types

enum PDFConversionError: LocalizedError {
    case invalidPDFFile
    case noTablesFound
    case fileWriteError
    case visionProcessingError
    case pageProcessingFailed(pageNumber: Int, reason: String)
    case insufficientMemory
    case processingCancelled
    case unsupportedPDFVersion

    var errorDescription: String? {
        switch self {
        case .invalidPDFFile:
            return "The selected file is not a valid PDF document."
        case .noTablesFound:
            return "No tables were found in the PDF document."
        case .fileWriteError:
            return "Failed to write the Excel file."
        case .visionProcessingError:
            return "Failed to process PDF content with Vision framework."
        case .pageProcessingFailed(let page, let reason):
            return "Failed to process page \(page): \(reason)"
        case .insufficientMemory:
            return "Not enough memory to process this PDF. Try closing other applications."
        case .processingCancelled:
            return "Processing was cancelled by the user."
        case .unsupportedPDFVersion:
            return "This PDF version is not supported. Try converting it to a newer format."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidPDFFile:
            return "Make sure the file is a valid PDF and not corrupted."
        case .noTablesFound:
            return "Ensure the PDF contains table-like structures with clear rows and columns."
        case .fileWriteError:
            return "Check that you have write permissions for the output directory."
        case .visionProcessingError:
            return "Try processing the PDF with a different accuracy setting."
        case .pageProcessingFailed:
            return "The page may contain complex content. Try extracting individual pages first."
        case .insufficientMemory:
            return "Try processing fewer pages at a time or restart the application."
        case .processingCancelled:
            return "You can retry processing if needed."
        case .unsupportedPDFVersion:
            return "Open the PDF in Preview or Adobe Reader and save it as a new file."
        }
    }
}

// MARK: - Processing Options

struct PDFProcessingOptions {
    var maxConcurrentPages: Int = 3
    var enableMemoryOptimization: Bool = true
    var minimumTableConfidence: Float = 0.3
    var minimumTableRows: Int = 2
    var useAutoreleasePool: Bool = true
    var imageScale: CGFloat = 2.0  // For Vision processing
    var enableProgressReporting: Bool = true
}

// MARK: - Processing Result

struct PDFProcessingResult {
    let processedPages: Int
    let tablesFound: Int
    let processingTime: TimeInterval
    let averageConfidence: Float
    let warnings: [String]
    let outputURL: URL
}

// MARK: - Enhanced Processor Extension

extension PDFToExcelConverter {

    // MARK: - Memory-Optimized Processing

    /// Process a PDF file with enhanced error handling and memory management
    func convertFileEnhanced(_ url: URL, options: PDFProcessingOptions = PDFProcessingOptions()) async throws -> PDFProcessingResult {
        let startTime = Date()
        var warnings: [String] = []

        // Validate PDF
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFConversionError.invalidPDFFile
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFConversionError.invalidPDFFile
        }

        logger.info("Starting enhanced processing of \(pageCount) pages")

        // Process pages in batches for memory efficiency
        var allTables: [TableData] = []
        let batchSize = options.maxConcurrentPages

        for batchStart in stride(from: 0, to: pageCount, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, pageCount)

            for pageIndex in batchStart..<batchEnd {
                // Allow cooperative cancellation
                try Task.checkCancellation()

                guard let page = pdfDocument.page(at: pageIndex) else {
                    warnings.append("Could not load page \(pageIndex + 1)")
                    continue
                }

                do {
                    // Render page image synchronously, optionally scoping with autoreleasepool
                    var cgImage: CGImage?
                    if options.useAutoreleasePool {
                        autoreleasepool {
                            cgImage = self.renderPageImage(page, scale: options.imageScale)
                        }
                    } else {
                        cgImage = self.renderPageImage(page, scale: options.imageScale)
                    }

                    guard let cgImage else {
                        warnings.append("Failed to render image for page \(pageIndex + 1)")
                        continue
                    }

                    let tables = try await self.extractTablesFromCGImage(
                        cgImage,
                        pageNumber: pageIndex + 1
                    )

                    // Filter by confidence
                    let filteredTables = tables.filter {
                        $0.confidence >= options.minimumTableConfidence &&
                        $0.rowCount >= options.minimumTableRows
                    }

                    allTables.append(contentsOf: filteredTables)

                    // Report progress if enabled
                    if options.enableProgressReporting {
                        let progress = Double(pageIndex + 1) / Double(pageCount)
                        await MainActor.run {
                            self.progress = progress
                        }
                    }
                } catch {
                    warnings.append("Failed to process page \(pageIndex + 1): \(error.localizedDescription)")
                    logger.error("Page processing error: \(error.localizedDescription)")
                }
            }
        }

        // Check if we found any tables
        guard !allTables.isEmpty else {
            logger.warning("No tables found in PDF document")
            throw PDFConversionError.noTablesFound
        }

        // Generate output file
        let outputURL = try generateExcelFile(from: allTables, originalURL: url)

        // Calculate statistics
        let processingTime = Date().timeIntervalSince(startTime)
        let averageConfidence = allTables.reduce(0.0) { $0 + $1.confidence } / Float(allTables.count)

        logger.info("Processing completed: \(allTables.count) tables found in \(processingTime)s")

        return PDFProcessingResult(
            processedPages: pageCount,
            tablesFound: allTables.count,
            processingTime: processingTime,
            averageConfidence: averageConfidence,
            warnings: warnings,
            outputURL: outputURL
        )
    }

    /// Synchronously render a CGImage for a PDF page at a given scale
    private func renderPageImage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        #if os(macOS)
        let nsImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return page.thumbnail(of: thumbnailSize, for: .mediaBox).cgImage
        #endif
    }

    // MARK: - Cancellable Processing

    /// Process files with cancellation support
    func convertFilesWithCancellation(
        _ urls: [URL],
        options: PDFProcessingOptions = PDFProcessingOptions()
    ) async throws -> [PDFProcessingResult] {
        var results: [PDFProcessingResult] = []

        await MainActor.run {
            self.isProcessing = true
            self.progress = 0.0
        }

        defer {
            Task { @MainActor in
                self.isProcessing = false
            }
        }

        for (index, url) in urls.enumerated() {
            // Check for cancellation
            try Task.checkCancellation()

            do {
                let result = try await convertFileEnhanced(url, options: options)
                results.append(result)

                // Create and store ProcessedFile
                let processedFile = ProcessedFile(
                    originalURL: url,
                    outputURL: result.outputURL,
                    fileName: url.deletingPathExtension().lastPathComponent,
                    pageCount: result.processedPages,
                    tablesFound: result.tablesFound,
                    processedDate: Date(),
                    fileSize: try FileManager.default.attributesOfItem(atPath: result.outputURL.path)[.size] as? Int64 ?? 0
                )

                await MainActor.run {
                    self.processedFiles.append(processedFile)
                }

                logger.info("Successfully converted: \(url.lastPathComponent)")

            } catch is CancellationError {
                logger.info("Processing cancelled by user")
                throw PDFConversionError.processingCancelled
            } catch {
                logger.error("Failed to convert \(url.lastPathComponent): \(error.localizedDescription)")
                throw error
            }

            // Update overall progress
            await MainActor.run {
                self.progress = Double(index + 1) / Double(urls.count)
            }
        }

        return results
    }
}

// MARK: - Memory Utilities

extension PDFToExcelConverter {

    /// Check available memory before processing
    func checkMemoryAvailability(for pdfDocument: PDFDocument) -> Bool {
        let pageCount = pdfDocument.pageCount

        // Rough estimate: 5MB per page for processing
        let estimatedMemoryMB = pageCount * 5

        // Get available memory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            logger.warning("Could not check memory availability")
            return true // Assume OK if we can't check
        }

        let availableMB = Int(info.resident_size) / 1024 / 1024
        let hasEnoughMemory = availableMB > estimatedMemoryMB

        if !hasEnoughMemory {
            logger.warning("Insufficient memory: need ~\(estimatedMemoryMB)MB, have ~\(availableMB)MB")
        }

        return hasEnoughMemory
    }
}

// MARK: - Validation Utilities

extension PDFToExcelConverter {

    /// Validate PDF before processing
    func validatePDF(_ url: URL) async -> Result<PDFDocument, PDFConversionError> {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.invalidPDFFile)
        }

        // Try to load PDF
        guard let pdfDocument = PDFDocument(url: url) else {
            return .failure(.invalidPDFFile)
        }

        // Check page count
        guard pdfDocument.pageCount > 0 else {
            return .failure(.invalidPDFFile)
        }

        // Check if PDF is encrypted or password-protected
        if pdfDocument.isEncrypted {
            logger.warning("PDF is encrypted - may not process correctly")
        }

        // Check memory availability
        guard checkMemoryAvailability(for: pdfDocument) else {
            return .failure(.insufficientMemory)
        }

        return .success(pdfDocument)
    }
}

// MARK: - Performance Metrics

struct ConversionMetrics {
    var totalTime: TimeInterval = 0
    var pagesProcessed: Int = 0
    var tablesExtracted: Int = 0
    var averageTimePerPage: TimeInterval {
        pagesProcessed > 0 ? totalTime / Double(pagesProcessed) : 0
    }
    var averageTablesPerPage: Double {
        pagesProcessed > 0 ? Double(tablesExtracted) / Double(pagesProcessed) : 0
    }
}

