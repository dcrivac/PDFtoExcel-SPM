//
//  DataModels.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import Foundation

// MARK: - Data Models

struct ProcessedFile: Identifiable, Hashable {
    let id = UUID()
    let originalURL: URL
    let outputURL: URL
    let fileName: String
    let pageCount: Int
    let tablesFound: Int
    let processedDate: Date
    let fileSize: Int64
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct TableData {
    let rows: [[String]]
    let columnCount: Int
    let rowCount: Int
    let confidence: Float
    let pageNumber: Int
}

// MARK: - TableData Extensions

extension TableData {
    // Note: aggressive OCR fixes should be opt-in if needed.
    var cleanedRows: [[String]] {
        return rows.map { row in
            row.map { cell in
                var cleaned = cell.trimmingCharacters(in: .whitespacesAndNewlines)

                // Remove common OCR noise
                cleaned = cleaned.replacingOccurrences(of: "|", with: "")
                cleaned = cleaned.replacingOccurrences(of: "~", with: "")

                // Only apply 0->O substitution if the cell looks alphabetic-only (no digits) and not numeric
                let alphabeticOnly = cleaned.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil
                if alphabeticOnly {
                    // No digits present; safe to correct stray zeros if any slipped in
                    cleaned = cleaned.replacingOccurrences(of: "0", with: "O")
                }

                return cleaned
            }
        }
    }
    
    var isEmpty: Bool {
        return rows.isEmpty || rows.allSatisfy { row in
            row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}

// MARK: - Error Types

enum ConversionError: LocalizedError {
    case invalidPDFFile
    case noTablesFound
    case fileWriteError
    case visionProcessingError
    
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
        }
    }
}
