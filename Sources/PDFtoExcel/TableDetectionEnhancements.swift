//
//  TableDetectionEnhancements.swift
//  PDFtoExcel
//
//  Advanced table detection algorithms for improved accuracy
//  Created by Assistant on 11/07/25.
//

import Foundation
import Vision
import PDFKit
import CoreGraphics
import OSLog

// MARK: - Enhanced Table Detection

final class EnhancedTableDetector: Sendable {
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "TableDetection")
    
    struct DetectionConfig {
        var yTolerance: CGFloat = 0.015  // Tighter tolerance for row grouping
        var minColumnWidth: CGFloat = 0.02  // Minimum column width
        var columnVarianceTolerance: Int = 2  // Allow up to 2 column variance
        var minTableRows: Int = 2
        var minConfidenceThreshold: Float = 0.4
        var useWhitespaceDetection: Bool = true
        var useBorderDetection: Bool = true
        var detectMergedCells: Bool = true
    }
    
    private let config = DetectionConfig()
    
    // MARK: - Advanced Table Detection
    
    func detectTables(from observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        var detectedTables: [TableData] = []
        
        // Try multiple detection strategies
        let whitespaceTable = detectWhitespaceTables(observations, pageNumber: pageNumber)
        let borderTable = detectBorderedTables(observations, pageNumber: pageNumber)
        let columnTable = detectColumnAlignedTables(observations, pageNumber: pageNumber)
        
        // Merge and deduplicate results
        detectedTables.append(contentsOf: whitespaceTable)
        detectedTables.append(contentsOf: borderTable)
        detectedTables.append(contentsOf: columnTable)
        
        // Remove duplicates and low-confidence tables
        return deduplicateAndFilter(detectedTables)
    }
    
    // MARK: - Whitespace-Based Detection
    
    private func detectWhitespaceTables(_ observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        // Group text by vertical position with tighter tolerance
        var rowGroups: [[VNRecognizedTextObservation]] = []
        var processedObservations = Set<ObjectIdentifier>()
        
        for observation in observations {
            guard !processedObservations.contains(ObjectIdentifier(observation)) else { continue }
            
            var currentRow = [observation]
            processedObservations.insert(ObjectIdentifier(observation))
            
            let yCenter = observation.boundingBox.midY
            
            // Find all observations on the same horizontal line
            for other in observations {
                guard !processedObservations.contains(ObjectIdentifier(other)) else { continue }
                
                let otherYCenter = other.boundingBox.midY
                if abs(yCenter - otherYCenter) <= config.yTolerance {
                    currentRow.append(other)
                    processedObservations.insert(ObjectIdentifier(other))
                }
            }
            
            if !currentRow.isEmpty {
                // Sort by X position
                currentRow.sort { $0.boundingBox.minX < $1.boundingBox.minX }
                rowGroups.append(currentRow)
            }
        }
        
        // Sort rows by Y position (top to bottom)
        rowGroups.sort { 
            $0.first?.boundingBox.midY ?? 0 > $1.first?.boundingBox.midY ?? 0 
        }
        
        // Identify column boundaries using whitespace analysis
        return identifyTableStructuresWithWhitespace(rowGroups, pageNumber: pageNumber)
    }
    
    private func identifyTableStructuresWithWhitespace(_ rowGroups: [[VNRecognizedTextObservation]], pageNumber: Int) -> [TableData] {
        var tables: [TableData] = []
        var currentTableRows: [[String]] = []
        var columnBoundaries: [CGFloat] = []
        
        for row in rowGroups {
            // Extract column positions from current row
            let positions = extractColumnPositions(from: row)
            
            if columnBoundaries.isEmpty {
                // Initialize column boundaries
                columnBoundaries = positions
                currentTableRows.append(extractTextFromRow(row, withColumns: columnBoundaries))
            } else {
                // Check if column structure is consistent
                let similarity = calculateColumnSimilarity(positions, columnBoundaries)
                
                if similarity > 0.7 {  // 70% similarity threshold
                    // Part of current table
                    currentTableRows.append(extractTextFromRow(row, withColumns: columnBoundaries))
                } else {
                    // Start of new table
                    if currentTableRows.count >= config.minTableRows {
                        let table = createTableData(from: currentTableRows, pageNumber: pageNumber)
                        tables.append(table)
                    }
                    
                    // Reset for new table
                    columnBoundaries = positions
                    currentTableRows = [extractTextFromRow(row, withColumns: columnBoundaries)]
                }
            }
        }
        
        // Add final table
        if currentTableRows.count >= config.minTableRows {
            let table = createTableData(from: currentTableRows, pageNumber: pageNumber)
            tables.append(table)
        }
        
        return tables
    }
    
    // MARK: - Column-Aligned Detection
    
    private func detectColumnAlignedTables(_ observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        // Detect natural column alignment across all observations
        let columnClusters = findColumnClusters(observations)
        
        guard columnClusters.count >= 2 else { return [] }
        
        // Group observations into rows based on Y position
        let rows = groupIntoRows(observations, usingColumns: columnClusters)
        
        // Convert to table data
        return rows.isEmpty ? [] : [createTableData(from: rows, pageNumber: pageNumber)]
    }
    
    private func findColumnClusters(_ observations: [VNRecognizedTextObservation]) -> [CGFloat] {
        // Collect all X positions
        var xPositions: [CGFloat] = []
        for obs in observations {
            xPositions.append(obs.boundingBox.minX)
        }
        
        // Sort and cluster nearby positions
        xPositions.sort()
        
        var clusters: [CGFloat] = []
        var currentCluster: [CGFloat] = []
        let clusterTolerance: CGFloat = 0.02
        
        for x in xPositions {
            if currentCluster.isEmpty {
                currentCluster.append(x)
            } else if let last = currentCluster.last, abs(x - last) <= clusterTolerance {
                currentCluster.append(x)
            } else {
                // Save current cluster and start new one
                if !currentCluster.isEmpty {
                    let average = currentCluster.reduce(0, +) / CGFloat(currentCluster.count)
                    clusters.append(average)
                }
                currentCluster = [x]
            }
        }
        
        // Add final cluster
        if !currentCluster.isEmpty {
            let average = currentCluster.reduce(0, +) / CGFloat(currentCluster.count)
            clusters.append(average)
        }
        
        return clusters
    }
    
    // MARK: - Bordered Table Detection
    
    private func detectBorderedTables(_ observations: [VNRecognizedTextObservation], pageNumber: Int) -> [TableData] {
        // Look for observations that form grid patterns
        var gridCells: [GridCell] = []
        
        for obs in observations {
            let cell = GridCell(
                text: obs.topCandidates(1).first?.string ?? "",
                bounds: obs.boundingBox,
                confidence: obs.confidence
            )
            gridCells.append(cell)
        }
        
        // Sort cells into grid structure
        let grid = organizeIntoGrid(gridCells)
        
        guard !grid.isEmpty else { return [] }
        
        // Convert grid to table data
        return [convertGridToTableData(grid, pageNumber: pageNumber)]
    }
    
    // MARK: - Helper Methods
    
    private func extractColumnPositions(from row: [VNRecognizedTextObservation]) -> [CGFloat] {
        return row.map { $0.boundingBox.minX }
    }
    
    private func calculateColumnSimilarity(_ positions1: [CGFloat], _ positions2: [CGFloat]) -> Float {
        let maxCount = max(positions1.count, positions2.count)
        guard maxCount > 0 else { return 0 }
        
        var matches = 0
        for pos1 in positions1 {
            for pos2 in positions2 {
                if abs(pos1 - pos2) <= config.minColumnWidth {
                    matches += 1
                    break
                }
            }
        }
        
        return Float(matches) / Float(maxCount)
    }
    
    private func extractTextFromRow(_ row: [VNRecognizedTextObservation], withColumns columns: [CGFloat]) -> [String] {
        var cells: [String] = Array(repeating: "", count: columns.count)
        
        for obs in row {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            
            // Find which column this text belongs to
            let x = obs.boundingBox.minX
            for (index, colX) in columns.enumerated() {
                if index < columns.count - 1 {
                    let nextColX = columns[index + 1]
                    if x >= colX && x < nextColX {
                        cells[index] = text
                        break
                    }
                } else {
                    // Last column
                    if x >= colX {
                        cells[index] = text
                    }
                }
            }
        }
        
        return cells
    }
    
    private func groupIntoRows(_ observations: [VNRecognizedTextObservation], usingColumns columns: [CGFloat]) -> [[String]] {
        // Group observations by Y coordinate
        var rowDict: [CGFloat: [VNRecognizedTextObservation]] = [:]
        
        for obs in observations {
            let y = round(obs.boundingBox.midY * 100) / 100  // Round to 2 decimal places
            if rowDict[y] == nil {
                rowDict[y] = []
            }
            rowDict[y]?.append(obs)
        }
        
        // Sort rows and extract text
        let sortedYs = rowDict.keys.sorted(by: >)
        var rows: [[String]] = []
        
        for y in sortedYs {
            guard let rowObs = rowDict[y] else { continue }
            let row = extractTextFromRow(rowObs, withColumns: columns)
            if !row.allSatisfy({ $0.isEmpty }) {
                rows.append(row)
            }
        }
        
        return rows
    }
    
    private func createTableData(from rows: [[String]], pageNumber: Int) -> TableData {
        let maxColumns = rows.map { $0.count }.max() ?? 0
        let confidence = calculateEnhancedConfidence(rows)
        
        return TableData(
            rows: rows,
            columnCount: maxColumns,
            rowCount: rows.count,
            confidence: confidence,
            pageNumber: pageNumber
        )
    }
    
    private func calculateEnhancedConfidence(_ rows: [[String]]) -> Float {
        guard rows.count >= 2 else { return 0.3 }
        
        var scores: [Float] = []
        
        // Column consistency score
        let columnCounts = rows.map { $0.count }
        let mostCommonCount = columnCounts.max() ?? 0
        let consistentRows = columnCounts.filter { $0 == mostCommonCount }.count
        scores.append(Float(consistentRows) / Float(rows.count))
        
        // Data density score (non-empty cells)
        let totalCells = rows.reduce(0) { $0 + $1.count }
        let filledCells = rows.reduce(0) { result, row in
            result + row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
        if totalCells > 0 {
            scores.append(Float(filledCells) / Float(totalCells))
        }
        
        // Numeric data presence score
        let numericCells = rows.reduce(0) { result, row in
            result + row.filter { cell in
                let cleaned = cell.replacingOccurrences(of: ",", with: "")
                                 .replacingOccurrences(of: "$", with: "")
                                 .replacingOccurrences(of: "%", with: "")
                return Double(cleaned) != nil
            }.count
        }
        if filledCells > 0 {
            scores.append(Float(numericCells) / Float(filledCells) * 0.5 + 0.5)
        }
        
        // Header detection score
        if rows.count > 1 {
            let firstRowNumeric = rows[0].filter { 
                Double($0.replacingOccurrences(of: ",", with: "")) != nil 
            }.count
            let dataRowsNumeric = rows.dropFirst().reduce(0) { result, row in
                result + row.filter { 
                    Double($0.replacingOccurrences(of: ",", with: "")) != nil 
                }.count
            }
            
            // If first row has fewer numbers than data rows, likely a header
            if firstRowNumeric < dataRowsNumeric / max(rows.count - 1, 1) {
                scores.append(0.9)
            } else {
                scores.append(0.6)
            }
        }
        
        // Calculate weighted average
        let weights: [Float] = [0.3, 0.2, 0.2, 0.3]
        var weightedSum: Float = 0
        var totalWeight: Float = 0
        
        for (index, score) in scores.enumerated() {
            if index < weights.count {
                weightedSum += score * weights[index]
                totalWeight += weights[index]
            }
        }
        
        return totalWeight > 0 ? weightedSum / totalWeight : 0.5
    }
    
    private func deduplicateAndFilter(_ tables: [TableData]) -> [TableData] {
        // Remove duplicates based on content similarity
        var uniqueTables: [TableData] = []
        
        for table in tables {
            // Check if this table is similar to any already added
            let isDuplicate = uniqueTables.contains { existing in
                calculateTableSimilarity(table, existing) > 0.8
            }
            
            if !isDuplicate && table.confidence >= config.minConfidenceThreshold {
                uniqueTables.append(table)
            }
        }
        
        // Sort by confidence
        return uniqueTables.sorted { $0.confidence > $1.confidence }
    }
    
    private func calculateTableSimilarity(_ table1: TableData, _ table2: TableData) -> Float {
        guard table1.rowCount == table2.rowCount,
              table1.columnCount == table2.columnCount else {
            return 0
        }
        
        var matchingCells = 0
        var totalCells = 0
        
        for (rowIndex, row1) in table1.rows.enumerated() {
            guard rowIndex < table2.rows.count else { break }
            let row2 = table2.rows[rowIndex]
            
            for (colIndex, cell1) in row1.enumerated() {
                guard colIndex < row2.count else { break }
                totalCells += 1
                if cell1 == row2[colIndex] {
                    matchingCells += 1
                }
            }
        }
        
        return totalCells > 0 ? Float(matchingCells) / Float(totalCells) : 0
    }
    
    // MARK: - Grid Structures
    
    private struct GridCell {
        let text: String
        let bounds: CGRect
        let confidence: Float
    }
    
    private func organizeIntoGrid(_ cells: [GridCell]) -> [[GridCell]] {
        guard !cells.isEmpty else { return [] }
        
        // Sort cells by Y position (top to bottom)
        let sortedCells = cells.sorted { $0.bounds.midY > $1.bounds.midY }
        
        var grid: [[GridCell]] = []
        var currentRow: [GridCell] = []
        var currentY = sortedCells.first?.bounds.midY ?? 0
        
        for cell in sortedCells {
            if abs(cell.bounds.midY - currentY) <= config.yTolerance {
                currentRow.append(cell)
            } else {
                if !currentRow.isEmpty {
                    // Sort row by X position
                    currentRow.sort { $0.bounds.minX < $1.bounds.minX }
                    grid.append(currentRow)
                }
                currentRow = [cell]
                currentY = cell.bounds.midY
            }
        }
        
        // Add final row
        if !currentRow.isEmpty {
            currentRow.sort { $0.bounds.minX < $1.bounds.minX }
            grid.append(currentRow)
        }
        
        return grid
    }
    
    private func convertGridToTableData(_ grid: [[GridCell]], pageNumber: Int) -> TableData {
        let rows = grid.map { row in
            row.map { $0.text }
        }
        
        let maxColumns = rows.map { $0.count }.max() ?? 0
        let normalizedRows = rows.map { row in
            var normalized = row
            while normalized.count < maxColumns {
                normalized.append("")
            }
            return normalized
        }
        
        return TableData(
            rows: normalizedRows,
            columnCount: maxColumns,
            rowCount: normalizedRows.count,
            confidence: calculateEnhancedConfidence(normalizedRows),
            pageNumber: pageNumber
        )
    }
}

// MARK: - Table Structure Analyzer

class TableStructureAnalyzer {
    
    func detectHeaders(in table: TableData) -> (hasHeader: Bool, headerRow: Int) {
        guard table.rowCount > 1 else { return (false, -1) }
        
        // Check if first row looks like headers
        let firstRow = table.rows[0]
        let dataRows = Array(table.rows.dropFirst())
        
        // Headers typically have:
        // 1. No numbers or fewer numbers than data rows
        // 2. Consistent text pattern
        // 3. Different formatting (we can't detect this from text alone)
        
        let firstRowNumericCount = countNumericCells(firstRow)
        let avgDataNumericCount = dataRows.reduce(0) { result, row in
            result + countNumericCells(row)
        } / max(dataRows.count, 1)
        
        // If first row has significantly fewer numbers, it's likely a header
        if firstRowNumericCount < avgDataNumericCount / 2 {
            return (true, 0)
        }
        
        return (false, -1)
    }
    
    func detectMergedCells(in table: TableData) -> [MergedCell] {
        var mergedCells: [MergedCell] = []
        
        for (rowIndex, row) in table.rows.enumerated() {
            for (colIndex, cell) in row.enumerated() {
                // Check if cell spans multiple columns
                if !cell.isEmpty && colIndex < row.count - 1 {
                    // Look for empty cells to the right
                    var span = 1
                    for nextCol in (colIndex + 1)..<row.count {
                        if row[nextCol].isEmpty {
                            span += 1
                        } else {
                            break
                        }
                    }
                    
                    if span > 1 {
                        mergedCells.append(MergedCell(
                            row: rowIndex,
                            column: colIndex,
                            rowSpan: 1,
                            columnSpan: span,
                            content: cell
                        ))
                    }
                }
            }
        }
        
        return mergedCells
    }
    
    private func countNumericCells(_ row: [String]) -> Int {
        return row.filter { cell in
            let cleaned = cell.replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: "%", with: "")
                            .trimmingCharacters(in: .whitespaces)
            return Double(cleaned) != nil
        }.count
    }
    
    struct MergedCell {
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let content: String
    }
}

// MARK: - Extended TableData

extension TableData {
    var normalizedRows: [[String]] {
        // Ensure all rows have the same number of columns
        let maxColumns = rows.map { $0.count }.max() ?? 0
        
        return rows.map { row in
            var normalized = row
            while normalized.count < maxColumns {
                normalized.append("")
            }
            return normalized
        }
    }
    
    var enhancedCleanedRows: [[String]] {
        return normalizedRows.map { row in
            row.map { cell in
                var cleaned = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Advanced OCR corrections
                cleaned = applyOCRCorrections(cleaned)
                
                // Format standardization
                cleaned = standardizeFormat(cleaned)
                
                return cleaned
            }
        }
    }
    
    private func applyOCRCorrections(_ text: String) -> String {
        var corrected = text
        
        // Context-aware corrections
        
        // If it looks like a number with misread characters
        if corrected.range(of: #"^\d+[lO]\d*$"#, options: .regularExpression) != nil {
            corrected = corrected.replacingOccurrences(of: "l", with: "1")
            corrected = corrected.replacingOccurrences(of: "O", with: "0")
        }
        
        // Common OCR mistakes in financial data
        corrected = corrected.replacingOccurrences(of: "S", with: "$", options: .regularExpression, range: corrected.startIndex..<corrected.index(corrected.startIndex, offsetBy: min(1, corrected.count)))
        
        // Fix percentage symbols
        if corrected.contains("o/o") {
            corrected = corrected.replacingOccurrences(of: "o/o", with: "%")
        }
        
        // Fix decimal points
        if corrected.range(of: #"\d+,\d{3}"#, options: .regularExpression) != nil {
            // Looks like thousands separator, leave it
        } else if corrected.range(of: #"\d+,\d{1,2}$"#, options: .regularExpression) != nil {
            // Might be European decimal, convert to US format
            corrected = corrected.replacingOccurrences(of: ",", with: ".")
        }
        
        return corrected
    }
    
    private func standardizeFormat(_ text: String) -> String {
        var standardized = text
        
        // Standardize currency symbols
        standardized = standardized.replacingOccurrences(of: "USD", with: "$")
        standardized = standardized.replacingOccurrences(of: "EUR", with: "â‚¬")
        
        // Remove extra spaces
        standardized = standardized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return standardized
    }
}
