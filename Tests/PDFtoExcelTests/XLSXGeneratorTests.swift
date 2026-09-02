//
//  XLSXGeneratorTests.swift
//  PDFtoExcelTests
//

import Foundation
import Testing
import ZIPFoundation
@testable import PDFtoExcel

/// A generated workbook, opened back up so its parts can be inspected.
struct Workbook {
    let url: URL
    private let archive: Archive
    
    init(tables: [TableData], options: XLSXOptions = XLSXOptions()) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFtoExcelTests-\(UUID().uuidString).xlsx")
        
        let detector = DataTypeDetector()
        try XLSXGenerator().generateXLSX(
            tables: tables,
            withDataTypes: tables.map { detector.detectColumnTypes(table: $0) },
            to: url,
            options: options
        )
        archive = try Archive(url: url, accessMode: .read)
    }
    
    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
    
    var partNames: [String] { archive.map(\.path) }
    
    /// One part's bytes, or nil if the package has no such part.
    func part(_ path: String) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }
    
    /// One part, parsed — which also asserts it is well formed.
    func xml(_ path: String) throws -> XMLDocument {
        let data = try #require(try part(path), "package has no part at \(path)")
        return try XMLDocument(data: data)
    }
    
    func text(_ path: String) throws -> String {
        String(decoding: try #require(try part(path)), as: UTF8.self)
    }
}

@Suite("XLSX output")
struct XLSXGeneratorTests {
    private func table(_ rows: [[String]], page: Int = 1, confidence: Float = 0.9) -> TableData {
        TableData(
            rows: rows,
            columnCount: rows.map(\.count).max() ?? 0,
            rowCount: rows.count,
            confidence: confidence,
            pageNumber: page
        )
    }
    
    private var priceList: TableData {
        table([
            ["Item", "Qty", "Price"],
            ["Bolt", "12", "$3.50"],
            ["Nut", "40", "$0.75"],
        ])
    }
    
    // MARK: - Package shape
    
    @Test("The parts sit at the root of the package, where a reader looks for them")
    func partsAreNotNested() throws {
        let workbook = try Workbook(tables: [priceList])
        defer { workbook.cleanUp() }
        
        #expect(workbook.partNames.contains("[Content_Types].xml"))
        #expect(workbook.partNames.contains("xl/workbook.xml"))
        #expect(workbook.partNames.contains("xl/worksheets/sheet1.xml"))
        #expect(workbook.partNames.allSatisfy { !$0.contains("../") })
    }
    
    @Test("Content types are declared first, as the package format requires")
    func contentTypesComeFirst() throws {
        let workbook = try Workbook(tables: [priceList])
        defer { workbook.cleanUp() }
        
        #expect(workbook.partNames.first == "[Content_Types].xml")
    }
    
    @Test("Every part the package declares is present, and every part present is declared")
    func declarationsMatchContents() throws {
        let workbook = try Workbook(tables: [priceList, table([["a", "b"], ["c", "d"]], page: 2)])
        defer { workbook.cleanUp() }
        
        let declared = try workbook.xml("[Content_Types].xml")
            .nodes(forXPath: "//*[local-name()='Override']/@PartName")
            .compactMap { $0.stringValue?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        
        for part in declared {
            #expect(workbook.partNames.contains(part), "declared but missing: \(part)")
        }
        for sheet in ["xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"] {
            #expect(declared.contains(sheet), "present but undeclared: \(sheet)")
        }
    }
    
    @Test("Every sheet the workbook lists resolves to a worksheet part")
    func relationshipsResolve() throws {
        let workbook = try Workbook(tables: [priceList, table([["a"], ["b"]], page: 2)])
        defer { workbook.cleanUp() }
        
        let ids = try workbook.xml("xl/workbook.xml")
            .nodes(forXPath: "//*[local-name()='sheet']/@*[local-name()='id']")
            .compactMap(\.stringValue)
        #expect(ids.count == 2)
        
        let rels = try workbook.xml("xl/_rels/workbook.xml.rels")
        for id in ids {
            let targets = try rels
                .nodes(forXPath: "//*[local-name()='Relationship'][@Id='\(id)']/@Target")
                .compactMap(\.stringValue)
            let target = try #require(targets.first, "no relationship for \(id)")
            #expect(workbook.partNames.contains("xl/\(target)"))
        }
    }
    
    @Test("Each part is well-formed XML")
    func partsParse() throws {
        let workbook = try Workbook(tables: [priceList])
        defer { workbook.cleanUp() }
        
        for part in workbook.partNames where part.hasSuffix(".xml") || part.hasSuffix(".rels") {
            #expect(throws: Never.self, "malformed: \(part)") {
                try workbook.xml(part)
            }
        }
    }
    
    // MARK: - Sheets
    
    @Test("A page becomes a sheet, named for the page it came from")
    func oneSheetPerPage() throws {
        let workbook = try Workbook(tables: [
            table([["a", "b"], ["c", "d"]], page: 1),
            table([["e", "f"], ["g", "h"]], page: 4),
        ])
        defer { workbook.cleanUp() }
        
        let names = try workbook.xml("xl/workbook.xml")
            .nodes(forXPath: "//*[local-name()='sheet']/@name")
            .compactMap(\.stringValue)
        
        #expect(names == ["Page 1", "Page 4"])
    }
    
    @Test("Two tables on one page get sheets with different names")
    func sheetNamesAreUnique() throws {
        let workbook = try Workbook(tables: [
            table([["a", "b"], ["c", "d"]], page: 3),
            table([["e", "f"], ["g", "h"]], page: 3),
        ])
        defer { workbook.cleanUp() }
        
        let names = try workbook.xml("xl/workbook.xml")
            .nodes(forXPath: "//*[local-name()='sheet']/@name")
            .compactMap(\.stringValue)
        
        // Excel refuses a workbook whose sheets share a name.
        #expect(names.count == 2)
        #expect(Set(names).count == 2)
    }
    
    @Test("Combining pages writes one sheet holding all of them")
    func combinedIntoOneSheet() throws {
        let workbook = try Workbook(
            tables: [priceList, table([["Screw", "7"]], page: 2)],
            options: XLSXOptions(separateByPage: false)
        )
        defer { workbook.cleanUp() }
        
        #expect(!workbook.partNames.contains("xl/worksheets/sheet2.xml"))
        
        let sheet = try workbook.text("xl/worksheets/sheet1.xml")
        #expect(sheet.contains("Bolt"))
        #expect(sheet.contains("Screw"))
    }
    
    // MARK: - Cells
    
    @Test("Text is written as text and figures as numbers")
    func cellTypes() throws {
        let workbook = try Workbook(tables: [priceList])
        defer { workbook.cleanUp() }
        
        let sheet = try workbook.text("xl/worksheets/sheet1.xml")
        
        #expect(sheet.contains("<t>Bolt</t>"))
        // The quantity is a number, not the characters "12".
        #expect(sheet.contains("<v>12.0</v>"))
        // And a price keeps its value once the currency symbol is off it.
        #expect(sheet.contains("<v>3.5</v>"))
    }
    
    @Test("A percentage is stored as the fraction it stands for")
    func percentagesAreFractions() throws {
        let workbook = try Workbook(tables: [table([
            ["Region", "Share"],
            ["North", "12%"],
            ["South", "40%"],
        ])])
        defer { workbook.cleanUp() }
        
        let sheet = try workbook.text("xl/worksheets/sheet1.xml")
        
        // Excel's percent format scales by a hundred on the way to the screen,
        // so 12% has to be stored as 0.12 to come back as 12%.
        #expect(sheet.contains("<v>0.12</v>"))
        #expect(!sheet.contains("<v>12.0</v>"))
    }
    
    @Test("A cell holding markup is escaped rather than breaking the sheet")
    func escapesMarkup() throws {
        let workbook = try Workbook(tables: [table([
            ["Item", "Note"],
            ["Bolt", "<b>M6</b> & up"],
            ["Nut", "plain"],
        ])])
        defer { workbook.cleanUp() }
        
        #expect(throws: Never.self) { try workbook.xml("xl/worksheets/sheet1.xml") }
        #expect(try workbook.text("xl/worksheets/sheet1.xml").contains("&lt;b&gt;M6&lt;/b&gt; &amp; up"))
    }
    
    @Test("An empty table still produces a readable sheet")
    func emptyTable() throws {
        let workbook = try Workbook(tables: [table([])])
        defer { workbook.cleanUp() }
        
        let sheet = try workbook.xml("xl/worksheets/sheet1.xml")
        let dimension = try sheet.nodes(forXPath: "//*[local-name()='dimension']/@ref").compactMap(\.stringValue)
        
        #expect(dimension == ["A1"])
    }
}
