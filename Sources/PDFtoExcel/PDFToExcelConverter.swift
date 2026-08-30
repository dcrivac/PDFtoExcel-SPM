import Foundation
import Combine
import SwiftUI
import OSLog
import PDFKit
#if os(macOS)
import AppKit
#endif

// Assuming ProcessedFile and ExcelWriter are defined elsewhere in the project

final class FileConversionManager: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var processedFiles: [ProcessedFile] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app", category: "FileConversion")
    
    // MARK: - Public Async Methods
    
    func convertFiles(_ urls: [URL]) async {
        isProcessing = true
        processedFiles = []
        progress = 0
        
        for (index, url) in urls.enumerated() {
            do {
                let processed = try await convertSingleFile(url)
                DispatchQueue.main.async {
                    self.processedFiles.append(processed)
                    self.progress = Double(index + 1) / Double(urls.count)
                }
            } catch {
                logger.error("Failed to convert file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async {
            self.isProcessing = false
        }
    }
    
    func convertSingleFile(_ url: URL) async throws -> ProcessedFile {
        // Basic validation: check file extension and PDF integrity
        guard url.pathExtension.lowercased() == "pdf" else {
            throw ConversionError.invalidFileExtension
        }
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ConversionError.invalidPDF
        }
        guard pdfDocument.pageCount > 0 else {
            throw ConversionError.emptyPDF
        }
        
        // Extract tables from each page (stub returns empty array)
        var extractedTables: [TableData] = []
        for pageIndex in 0..<pdfDocument.pageCount {
            let tables: [TableData] = extractTablesFromPage(pdfDocument.page(at: pageIndex), pageNumber: pageIndex + 1)
            extractedTables.append(contentsOf: tables)
        }
        
        // Generate Excel (CSV) file from extracted tables
        let outputURL = try generateExcelFile(from: extractedTables, originalURL: url)
        
        return ProcessedFile(originalURL: url, outputURL: outputURL)
    }
    
    // MARK: - Stubs / Helpers
    
    /// Stub method to extract tables from a PDF page, returns an empty array by default
    func extractTablesFromPage(_ page: PDFPage?, pageNumber: Int) -> [TableData] {
        return []
    }
    
    /// Generates Excel file from extracted tables, uses ExcelWriter to write CSV, returns output URL
    func generateExcelFile(from tables: [TableData], originalURL: URL) throws -> URL {
        // Determine output URL in temporary directory with same base name but .csv extension
        let outputFileName = originalURL.deletingPathExtension().lastPathComponent + ".csv"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        let writer = ExcelWriter()
        try writer.writeCSV(tables: tables, to: outputURL)
        
        return outputURL
    }
    
    // MARK: - Platform-Safe Helpers
    
    /// Opens the output file using platform-appropriate method
    func openOutputFile(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        // iOS open file with UIDocumentInteractionController or share sheet (no-op here)
        #else
        // Other platforms no-op
        #endif
    }
    
    /// Reveals the output file in Finder (macOS only)
    func revealInFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        // No-op on non-macOS platforms
        #endif
    }
    
    // MARK: - Errors
    
    enum ConversionError: LocalizedError {
        case invalidFileExtension
        case invalidPDF
        case emptyPDF
        
        var errorDescription: String? {
            switch self {
            case .invalidFileExtension:
                return "The file does not have a PDF extension."
            case .invalidPDF:
                return "The PDF file could not be opened or is invalid."
            case .emptyPDF:
                return "The PDF file contains no pages."
            }
        }
    }
}

extension ProcessedFile {
    init(originalURL: URL, outputURL: URL) {
        let fileName = originalURL.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: originalURL.path)) ?? [:]
        let fileSize = attributes[.size] as? Int64 ?? 0
        self.init(originalURL: originalURL, outputURL: outputURL, fileName: fileName, pageCount: 0, tablesFound: 0, processedDate: Date(), fileSize: fileSize)
    }
}
