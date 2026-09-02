//
//  CSVWritingTests.swift
//  PDFtoExcelTests
//

import Foundation
import Testing
@testable import PDFtoExcel

@Suite("CSV output")
struct CSVWritingTests {
    let writer = ExcelWriter()
    
    private func table(_ rows: [[String]], page: Int = 1) -> TableData {
        TableData(
            rows: rows,
            columnCount: rows.map(\.count).max() ?? 0,
            rowCount: rows.count,
            confidence: 0.9,
            pageNumber: page
        )
    }
    
    /// Writes to a scratch file and hands back what landed on disk.
    private func write(
        _ tables: [TableData],
        separateByPage: Bool = true
    ) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFtoExcelTests-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        
        try writer.writeCSV(tables: tables, to: url, separateByPage: separateByPage)
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    @Test("Rows are written in order, one line each")
    func writesRows() throws {
        let csv = try write([table([["Item", "Qty"], ["Bolt", "12"]])], separateByPage: false)
        
        #expect(csv.contains("Item,Qty\n"))
        #expect(csv.contains("Bolt,12\n"))
    }
    
    @Test("A cell holding a comma is quoted")
    func quotesCommas() throws {
        let csv = try write([table([["Acme, Inc.", "12"], ["Nut", "40"]])], separateByPage: false)
        
        #expect(csv.contains("\"Acme, Inc.\",12"))
    }
    
    @Test("A quote inside a cell is doubled")
    func escapesQuotes() throws {
        let csv = try write([table([["3\" bolt", "12"], ["Nut", "40"]])], separateByPage: false)
        
        #expect(csv.contains("\"3\"\" bolt\",12"))
    }
    
    @Test("An ordinary cell is written bare")
    func leavesPlainCellsAlone() {
        #expect(writer.formatCSVCell("Bolt") == "Bolt")
        #expect(writer.formatCSVCell("3.50") == "3.50")
    }
    
    @Test("Each page gets a header when pages are kept apart")
    func labelsPages() throws {
        let csv = try write([
            table([["Bolt", "12"]], page: 1),
            table([["Nut", "40"]], page: 2),
        ])
        
        #expect(csv.contains("Page 1"))
        #expect(csv.contains("Page 2"))
    }
    
    @Test("Combining pages writes the rows continuously")
    func combinesPages() throws {
        let csv = try write([
            table([["Bolt", "12"]], page: 1),
            table([["Nut", "40"]], page: 2),
        ], separateByPage: false)
        
        #expect(csv.contains("Bolt,12"))
        #expect(csv.contains("Nut,40"))
        #expect(csv.contains("--- Page 2"))
    }
    
    @Test("Empty tables are dropped rather than written as blank lines")
    func skipsEmptyTables() throws {
        let csv = try write([
            table([["", ""]]),
            table([["Bolt", "12"], ["Nut", "40"]], page: 2),
        ], separateByPage: false)
        
        #expect(csv.contains("Bolt,12"))
        #expect(!csv.contains("Page 1"))
    }
    
    @Test("Writing nothing but empty tables reports that no tables were found")
    func refusesEmptyOutput() {
        #expect(throws: ConversionError.noTablesFound) {
            try write([table([["", ""]])])
        }
    }
}
