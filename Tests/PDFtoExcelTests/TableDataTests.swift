//
//  TableDataTests.swift
//  PDFtoExcelTests
//

import Foundation
import Testing
@testable import PDFtoExcel

@Suite("Table data")
struct TableDataTests {
    private func table(_ rows: [[String]]) -> TableData {
        TableData(
            rows: rows,
            columnCount: rows.map(\.count).max() ?? 0,
            rowCount: rows.count,
            confidence: 0.9,
            pageNumber: 1
        )
    }
    
    @Test("Cleaning trims cells and drops OCR noise")
    func cleaningRemovesNoise() {
        let cleaned = table([["  Bolt  ", "|12|", "3.50~"]]).cleanedRows
        
        #expect(cleaned == [["Bolt", "12", "3.50"]])
    }
    
    @Test("Cleaning leaves a figure's digits alone")
    func cleaningKeepsDigits() {
        let cleaned = table([["1024", "0.75", "R0AD"]]).cleanedRows
        
        // The zero-to-letter correction only fires on cells that are already
        // alphabetic throughout, which by definition hold no zero to correct —
        // so nothing is ever substituted. Pinned as it stands: a reading of
        // "R0AD" for "ROAD" is left uncorrected rather than a price being
        // mangled into letters.
        #expect(cleaned == [["1024", "0.75", "R0AD"]])
    }
    
    @Test("A table of blanks counts as empty")
    func blankTableIsEmpty() {
        #expect(table([["", "  "], ["", ""]]).isEmpty)
        #expect(table([]).isEmpty)
    }
    
    @Test("A table with any content is not empty")
    func filledTableIsNotEmpty() {
        #expect(!table([["", "12"]]).isEmpty)
    }
    
    @Test("A table round-trips through its encoded form")
    func codableRoundTrip() throws {
        let original = table([["Item", "Qty"], ["Bolt", "12"]])
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TableData.self, from: data)
        
        #expect(decoded.rows == original.rows)
        #expect(decoded.columnCount == original.columnCount)
        #expect(decoded.pageNumber == original.pageNumber)
    }
}
