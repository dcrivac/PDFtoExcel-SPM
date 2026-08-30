//
//  ExcelWriter.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import Foundation
import OSLog

class ExcelWriter {
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "ExcelWriter")
    
    func writeCSV(tables: [TableData], to url: URL, separateByPage: Bool = true) throws {
        // Filter out empty tables using the TableData extension
        let validTables = tables.filter { !$0.isEmpty }
        
        guard !validTables.isEmpty else {
            throw ConversionError.noTablesFound
        }
        
        var csvContent = ""
        
        if separateByPage {
            // Write each page's tables separately with page headers
            for table in validTables {
                if !csvContent.isEmpty {
                    csvContent += "\n\n" // Add spacing between pages
                }
                
                csvContent += "Page \(table.pageNumber) (Confidence: \(String(format: "%.1f", table.confidence * 100))%)\n"
                csvContent += String(repeating: "-", count: 50) + "\n"
                
                for row in table.cleanedRows {
                    let escapedRow = row.map(escapeCSVCell)
                    csvContent += escapedRow.joined(separator: ",") + "\n"
                }
            }
        } else {
            // Combine all tables into one continuous CSV
            var allRows: [[String]] = []
            
            for table in validTables {
                // Add a page separator row if combining pages
                if !allRows.isEmpty {
                    let separator = "--- Page \(table.pageNumber) (Confidence: \(String(format: "%.1f", table.confidence * 100))%) ---"
                    allRows.append([separator])
                    allRows.append([]) // Empty row for spacing
                }
                allRows.append(contentsOf: table.cleanedRows)
            }
            
            for row in allRows {
                let escapedRow = row.map(escapeCSVCell)
                csvContent += escapedRow.joined(separator: ",") + "\n"
            }
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Successfully wrote CSV file: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to write CSV file: \(error.localizedDescription)")
            throw ConversionError.fileWriteError
        }
    }
    
    private func escapeCSVCell(_ cell: String) -> String {
        // Escape cells containing commas, quotes, or newlines
        if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
            return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return cell
    }
    
    // Legacy method name for backward compatibility
    func formatCSVCell(_ cell: String) -> String {
        return escapeCSVCell(cell)
    }
    
    // NOTE: Placeholder implementation.
    // This method currently writes a CSV and then moves/renames it to .xlsx.
    // The resulting file is not a true XLSX workbook. To produce real Excel files,
    // implement XLSX packaging (ZIP + XML parts) or use an appropriate library.
    func writeXLSX(tables: [TableData], to url: URL, separateByPage: Bool = true) throws {
        // For now, fall back to CSV format
        // In a real implementation, you'd use a library like xlsxwriter or create XML manually
        let csvURL = url.appendingPathExtension("csv")
        try writeCSV(tables: tables, to: csvURL, separateByPage: separateByPage)
        
        // Move the CSV file to have XLSX extension (placeholder)
        do {
            try FileManager.default.moveItem(at: csvURL, to: url)
            logger.info("Created placeholder XLSX by moving CSV: \(url.lastPathComponent)")
        } catch {
            logger.error("Failed to create XLSX file: \(error.localizedDescription)")
            throw ConversionError.fileWriteError
        }
    }
}

