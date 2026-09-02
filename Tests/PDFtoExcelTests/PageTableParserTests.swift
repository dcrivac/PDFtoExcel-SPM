//
//  PageTableParserTests.swift
//  PDFtoExcelTests
//

import CoreGraphics
import Testing
@testable import PDFtoExcel

@Suite("Page table parsing")
struct PageTableParserTests {
    let parser = PageTableParser()
    
    // MARK: - Row grouping
    
    @Test("Runs sharing a baseline become one row, ordered down the page")
    func groupsRunsIntoRows() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
        ], columnX: [0.1, 0.4, 0.7])
        
        let rows = parser.rows(from: runs)
        
        #expect(rows.map { $0.cells.map(\.text) } == [
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
        ])
    }
    
    @Test("Cells are ordered left to right whatever order OCR reported them in")
    func sortsCellsByPosition() {
        let runs = [
            Page.run("Price", x: 0.7, y: 0.9),
            Page.run("Item", x: 0.1, y: 0.9),
            Page.run("Qty", x: 0.4, y: 0.9),
        ]
        
        let rows = parser.rows(from: runs)
        
        #expect(rows.count == 1)
        #expect(rows[0].cells.map(\.text) == ["Item", "Qty", "Price"])
    }
    
    // MARK: - Column alignment
    
    @Test("A blank cell stays blank instead of shifting its row left")
    func blankCellHoldsItsColumn() {
        let runs = Page.grid([
            ["Item", "Qty", "Price"],
            ["Bolt", "", "3.50"],
            ["Nut", "40", "0.75"],
        ], columnX: [0.1, 0.4, 0.7])
        
        let tables = parser.tables(from: runs, pageNumber: 1)
        
        #expect(tables.count == 1)
        #expect(tables[0].rows[1] == ["Bolt", "", "3.50"])
        #expect(tables[0].columnCount == 3)
    }
    
    @Test("A centred column is read by its centre, not its left edge")
    func readsCentredColumns() {
        // Read by the left edge these three cells sit up to five hundredths of a
        // page apart — well beyond the clustering tolerance — and the column
        // fragments. Their centres agree exactly.
        let runs = Page.centredGrid([
            ["Alpha", "Widget"],
            ["Beta", "Nut"],
            ["Gamma", "Fastener"],
        ], columnX: [0.15, 0.5])
        
        let tables = parser.tables(from: runs, pageNumber: 1)
        
        #expect(tables.count == 1)
        #expect(tables[0].columnCount == 2)
        #expect(tables[0].rows == [
            ["Alpha", "Widget"],
            ["Beta", "Nut"],
            ["Gamma", "Fastener"],
        ])
    }
    
    @Test("A column of figures sharing a right edge stays one column")
    func readsRightAlignedColumns() {
        let runs = Page.rightAlignedGrid([
            ["Bolt", "1.00"],
            ["Nut", "22.50"],
            ["Washer", "1234.75"],
        ], columnX: [0.25, 0.8])
        
        let tables = parser.tables(from: runs, pageNumber: 1)
        
        #expect(tables.count == 1)
        #expect(tables[0].columnCount == 2)
        #expect(tables[0].rows.map { $0[1] } == ["1.00", "22.50", "1234.75"])
    }
    
    @Test("Two runs landing in one column are joined rather than one being lost")
    func joinsRunsSharingAColumn() {
        let row = PageTableParser.TextRow(y: 0.5, cells: [
            Page.run("Acme", x: 0.10, y: 0.5, width: 0.09),
            Page.run("Industries", x: 0.20, y: 0.5, width: 0.09),
            Page.run("42", x: 0.70, y: 0.5, width: 0.04),
        ])
        
        let cells = parser.alignCells(of: row, to: [0.15, 0.70], using: .leading)
        
        #expect(cells == ["Acme Industries", "42"])
    }
    
    // MARK: - Splitting a page into tables
    
    @Test("A one-cell heading closes the table above it")
    func headingSplitsTables() {
        let rows = [
            PageTableParser.TextRow(y: 0.90, cells: [Page.run("Bolt", x: 0.1, y: 0.90), Page.run("12", x: 0.5, y: 0.90)]),
            PageTableParser.TextRow(y: 0.86, cells: [Page.run("Nut", x: 0.1, y: 0.86), Page.run("40", x: 0.5, y: 0.86)]),
            PageTableParser.TextRow(y: 0.82, cells: [Page.run("Fasteners", x: 0.1, y: 0.82)]),
            PageTableParser.TextRow(y: 0.78, cells: [Page.run("Screw", x: 0.1, y: 0.78), Page.run("7", x: 0.5, y: 0.78)]),
            PageTableParser.TextRow(y: 0.74, cells: [Page.run("Rivet", x: 0.1, y: 0.74), Page.run("9", x: 0.5, y: 0.74)]),
        ]
        
        let groups = parser.splitRowsIntoTables(rows)
        
        // The heading is isolated into a group of its own, which then falls
        // below the two-row minimum and is dropped downstream.
        #expect(groups.map(\.count) == [2, 1, 2])
    }
    
    @Test("A gap far larger than the page's line spacing separates two tables")
    func verticalGapSplitsTables() {
        let rows = [
            PageTableParser.TextRow(y: 0.90, cells: [Page.run("Bolt", x: 0.1, y: 0.90), Page.run("12", x: 0.5, y: 0.90)]),
            PageTableParser.TextRow(y: 0.86, cells: [Page.run("Nut", x: 0.1, y: 0.86), Page.run("40", x: 0.5, y: 0.86)]),
            PageTableParser.TextRow(y: 0.50, cells: [Page.run("Screw", x: 0.1, y: 0.50), Page.run("7", x: 0.5, y: 0.50)]),
            PageTableParser.TextRow(y: 0.46, cells: [Page.run("Rivet", x: 0.1, y: 0.46), Page.run("9", x: 0.5, y: 0.46)]),
        ]
        
        let groups = parser.splitRowsIntoTables(rows)
        
        #expect(groups.map(\.count) == [2, 2])
    }
    
    @Test("Evenly spaced rows stay in one table")
    func evenSpacingIsOneTable() {
        let runs = Page.grid([
            ["Bolt", "12"],
            ["Nut", "40"],
            ["Screw", "7"],
        ], columnX: [0.1, 0.5])
        
        #expect(parser.splitRowsIntoTables(parser.rows(from: runs)).count == 1)
    }
    
    // MARK: - Tilt
    
    @Test("A tilted page is levelled before its rows are read")
    func levelsTiltedPages() {
        // Across the full width this tilt lifts a row by more than the row
        // grouping tolerance, so read as it stands every printed line would
        // break into several.
        let runs = Page.grid([
            ["Item", "Qty", "Price", "Total"],
            ["Bolt", "12", "3.50", "42.00"],
            ["Nut", "40", "0.75", "30.00"],
            ["Screw", "7", "1.25", "8.75"],
            ["Rivet", "9", "2.00", "18.00"],
        ], columnX: [0.1, 0.3, 0.5, 0.7], slope: 0.05)
        
        let rows = parser.rows(from: runs)
        
        #expect(rows.map { $0.cells.map(\.text) } == [
            ["Item", "Qty", "Price", "Total"],
            ["Bolt", "12", "3.50", "42.00"],
            ["Nut", "40", "0.75", "30.00"],
            ["Screw", "7", "1.25", "8.75"],
            ["Rivet", "9", "2.00", "18.00"],
        ])
    }
    
    @Test("A square page is left alone")
    func squarePageIsNotNudged() {
        let runs = Page.grid([
            ["Item", "Qty", "Price", "Total"],
            ["Bolt", "12", "3.50", "42.00"],
            ["Nut", "40", "0.75", "30.00"],
            ["Screw", "7", "1.25", "8.75"],
        ], columnX: [0.1, 0.3, 0.5, 0.7])
        
        #expect(TextSkew.estimateSlope(of: runs) == 0)
    }
    
    @Test("Too little text to judge reports square rather than guessing")
    func tooLittleTextIsSquare() {
        let runs = Page.grid([["Item", "Qty"]], columnX: [0.1, 0.5], slope: 0.08)
        
        #expect(TextSkew.estimateSlope(of: runs) == 0)
    }
    
    // MARK: - Clustering
    
    @Test("Positions within the tolerance become one column reference")
    func clustersNearbyPositions() {
        #expect(parser.cluster([0.100, 0.105, 0.112]).count == 1)
        #expect(parser.cluster([0.10, 0.50]).count == 2)
    }
    
    @Test("Clustering an empty page yields no columns")
    func clustersNothing() {
        #expect(parser.cluster([]).isEmpty)
    }
    
    // MARK: - Confidence
    
    @Test("A consistent table of figures scores above a ragged one")
    func confidenceRewardsStructure() {
        let clean = parser.calculateTableConfidence([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "3.50"],
            ["Nut", "40", "0.75"],
        ])
        let ragged = parser.calculateTableConfidence([
            ["Some prose that ran on"],
            ["and wrapped", "oddly"],
            ["with", "no", "shape"],
        ])
        
        #expect(clean > ragged)
    }
    
    @Test("A single row cannot establish a structure")
    func singleRowHasNoConfidence() {
        #expect(parser.calculateTableConfidence([["Item", "Qty"]]) == 0)
    }
    
    // MARK: - Whole-page parsing
    
    @Test("A page with no repeated structure yields no tables")
    func noStructureNoTables() {
        #expect(parser.tables(from: [], pageNumber: 1).isEmpty)
        
        let single = Page.grid([["Item", "Qty"]], columnX: [0.1, 0.5])
        #expect(parser.tables(from: single, pageNumber: 1).isEmpty)
    }
    
    @Test("The page number is carried onto every table found")
    func carriesPageNumber() {
        let runs = Page.grid([
            ["Bolt", "12"],
            ["Nut", "40"],
        ], columnX: [0.1, 0.5])
        
        #expect(parser.tables(from: runs, pageNumber: 7).allSatisfy { $0.pageNumber == 7 })
    }
}
