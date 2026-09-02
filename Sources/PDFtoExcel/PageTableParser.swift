//
//  PageTableParser.swift
//  PDFtoExcel
//
//  The default engine's page-to-tables parsing.
//

import CoreGraphics
import Foundation

/// Turns one page's recognized text into tables.
///
/// This is the default engine's reading of a page, split out from the converter
/// that drives it: it holds no state, touches no UI and knows nothing about
/// PDFs, so each stage can be exercised on positions written by hand.
struct PageTableParser {
    /// One OCR'd line: its vertical position and the text runs found on it.
    struct TextRow {
        var y: CGFloat
        var cells: [TextRun]
    }
    
    /// Where a column's cells line up with one another.
    ///
    /// A column may be left, centre or right aligned, and only the matching
    /// edge stays put as cell contents change width. Reading a centred column
    /// by its left edge scatters every differently sized cell into a column of
    /// its own.
    enum ColumnAnchor: CaseIterable {
        case leading, center, trailing
        
        func position(of run: TextRun) -> CGFloat {
            switch self {
            case .leading:  return run.minX
            case .center:   return (run.minX + run.maxX) / 2
            case .trailing: return run.maxX
            }
        }
    }
    
    func tables(from runs: [TextRun], pageNumber: Int) -> [TableData] {
        let pageRows = rows(from: runs)
        
        return splitRowsIntoTables(pageRows).compactMap { group -> TableData? in
            // Two rows is the minimum that can establish a repeated structure.
            guard group.count >= 2 else { return nil }
            
            let layout = columnLayout(in: group)
            let columns = layout.positions
            guard columns.count >= 2 else { return nil }
            
            let tableRows = group.map { alignCells(of: $0, to: columns, using: layout.anchor) }
            
            return TableData(
                rows: tableRows,
                columnCount: columns.count,
                rowCount: tableRows.count,
                confidence: calculateTableConfidence(tableRows),
                pageNumber: pageNumber
            )
        }
    }
    
    /// Collect runs onto shared baselines, top to bottom.
    func rows(from runs: [TextRun]) -> [TextRow] {
        let yTolerance: CGFloat = 0.02
        var rows: [TextRow] = []
        
        // A scanned page is rarely square to the platen, and past about two
        // degrees the climb across a row exceeds the tolerance below, splitting
        // one printed line into two. Level the page first.
        let slope = TextSkew.estimateSlope(of: runs)
        
        // midY rather than the bottom edge: cells on one line differ in height,
        // so their baselines separate further than their centres do.
        for run in runs.sorted(by: {
            TextSkew.deskewedY($0, slope: slope) > TextSkew.deskewedY($1, slope: slope)
        }) {
            let text = run.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            
            let y = TextSkew.deskewedY(run, slope: slope)
            var cell = run
            cell.text = text
            
            if let index = rows.firstIndex(where: { abs($0.y - y) <= yTolerance }) {
                rows[index].cells.append(cell)
            } else {
                rows.append(TextRow(y: y, cells: [cell]))
            }
        }
        
        for index in rows.indices {
            rows[index].cells.sort { $0.minX < $1.minX }
        }
        return rows
    }
    
    /// Break the page's rows where one table ends and the next begins.
    ///
    /// A row holding a single run is a heading rather than data, so it closes the
    /// table above it and is isolated into a group of its own, which then falls
    /// below the two-row minimum and is dropped. A vertical gap far larger than
    /// the page's usual line spacing separates tables that carry no heading.
    func splitRowsIntoTables(_ rows: [TextRow]) -> [[TextRow]] {
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
    
    /// Work out how this table's columns line up, and where they sit.
    ///
    /// The correct anchor is the one that actually collapses the table: read by
    /// the wrong edge a column fragments into several, so the anchor yielding
    /// the fewest columns that can still hold the widest row is the one the
    /// table is really using.
    func columnLayout(in rows: [TextRow]) -> (anchor: ColumnAnchor, positions: [CGFloat]) {
        var best: (anchor: ColumnAnchor, positions: [CGFloat], occupancy: Double)?
        
        for anchor in ColumnAnchor.allCases {
            let positions = cluster(rows.flatMap { $0.cells.map(anchor.position) })
            guard positions.count >= 2 else { continue }
            
            // Read by the wrong edge, a column splits in two and each half sits
            // empty on the rows that do not reach it. The right anchor is the
            // one whose columns are actually filled.
            let filled = rows.reduce(0) { total, row in
                total + Set(row.cells.map { nearestColumn(to: anchor.position(of: $0), in: positions) }).count
            }
            let occupancy = Double(filled) / Double(rows.count * positions.count)
            
            // On a tie, more columns means a finer reading of the same layout.
            let better = best.map { occupancy > $0.occupancy + 0.001
                || (abs(occupancy - $0.occupancy) <= 0.001 && positions.count > $0.positions.count) } ?? true
            if better {
                best = (anchor, positions, occupancy)
            }
        }
        
        if let best { return (best.anchor, best.positions) }
        return (.leading, cluster(rows.flatMap { $0.cells.map(ColumnAnchor.leading.position) }))
    }
    
    /// Index of the column reference nearest a position.
    func nearestColumn(to x: CGFloat, in columns: [CGFloat]) -> Int {
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, position) in columns.enumerated() {
            let distance = abs(position - x)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
    
    /// Group nearby positions into one reference each.
    func cluster(_ values: [CGFloat]) -> [CGFloat] {
        let tolerance: CGFloat = 0.02
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [] }
        
        var clusters: [[CGFloat]] = [[sorted[0]]]
        for x in sorted.dropFirst() {
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
    func alignCells(of row: TextRow, to columns: [CGFloat], using anchor: ColumnAnchor) -> [String] {
        guard !columns.isEmpty else { return [] }
        var cells = [String](repeating: "", count: columns.count)
        
        for cell in row.cells {
            let x = anchor.position(of: cell)
            var bestIndex = 0
            var bestDistance = abs(columns[0] - x)
            for (index, position) in columns.enumerated().dropFirst() {
                let distance = abs(position - x)
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
    
    func calculateTableConfidence(_ rows: [[String]]) -> Float {
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
}
