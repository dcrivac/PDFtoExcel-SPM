//
//  EnhancedTableDetectorTests.swift
//  PDFtoExcelTests
//

import Testing
@testable import PDFtoExcel

@Suite("Enhanced table detection")
struct EnhancedTableDetectorTests {
    let detector = EnhancedTableDetector()
    
    @Test("A page of body text is not a table")
    func prosePageYieldsNoTables() {
        // Vision returns a body line as one run, so every line agrees on where
        // its single column starts. That is a column, but it is not a table.
        let prose = Page.grid([
            ["The quarterly review covered three regions"],
            ["and closed with a summary of the year to"],
            ["date, which the board accepted without any"],
            ["further discussion or amendment."],
        ], columnX: [0.1], cellWidth: 0.8)
        
        #expect(detector.detectTables(from: prose, pageNumber: 1).isEmpty)
    }
    
    @Test("A real table survives detection")
    func tableIsDetected() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
            ["Screw", "7", "1.25"],
        ], columnX: [0.1, 0.4, 0.7])
        
        let tables = detector.detectTables(from: runs, pageNumber: 1)
        
        #expect(!tables.isEmpty)
        #expect(tables.allSatisfy { $0.columnCount >= 2 })
        #expect(tables.contains { $0.rows.contains(["Item", "Qty", "Price"]) })
    }
    
    @Test("The same table found by several strategies is reported once")
    func duplicatesAreCollapsed() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
            ["Screw", "7", "1.25"],
        ], columnX: [0.1, 0.4, 0.7])
        
        let tables = detector.detectTables(from: runs, pageNumber: 1)
        
        // Three strategies run over this page and each recovers it; only one
        // reading should come back.
        #expect(tables.count == 1)
    }
    
    @Test("A table whose rows mostly hold a single value is treated as prose")
    func sparseRowsAreRejected() {
        // The boundary the `isTabular` filter draws: most rows have to reach
        // more than one column. A list with an occasional second value does
        // not, and is indistinguishable from a run of text to the detector.
        let sparse = Page.grid([
            ["Introduction", ""],
            ["Background", ""],
            ["Method", "12"],
            ["Results", ""],
            ["Discussion", ""],
        ], columnX: [0.1, 0.7])
        
        #expect(detector.detectTables(from: sparse, pageNumber: 1).isEmpty)
    }
    
    @Test("Blank cells do not push a row's values into the wrong column")
    func blankCellsHoldTheirColumn() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "", "3.50"],
            ["Nut", "40", "0.75"],
        ], columnX: [0.1, 0.4, 0.7])
        
        // Known issue: the bordered strategy's `convertGridToTableData` takes a
        // row's cells in x order and pads the end, so a blank cell shifts every
        // value after it one column left — "3.50" is reported under "Qty". The
        // default engine fixed this by placing each cell in the column it sits
        // under; the same fix has not been applied here. Remove the wrapper
        // once it has.
        withKnownIssue("Bordered strategy pads row ends instead of placing cells by position") {
            let tables = detector.detectTables(from: runs, pageNumber: 1)
            
            #expect(tables.contains { table in
                table.rows.contains { $0.count == 3 && $0[0] == "Bolt" && $0[2] == "3.50" }
            })
        }
    }
    
    @Test("An empty page yields no tables")
    func emptyPage() {
        #expect(detector.detectTables(from: [], pageNumber: 1).isEmpty)
    }
    
    @Test("Every table carries the page it came from")
    func carriesPageNumber() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
        ], columnX: [0.1, 0.4, 0.7])
        
        #expect(detector.detectTables(from: runs, pageNumber: 4).allSatisfy { $0.pageNumber == 4 })
    }
}
