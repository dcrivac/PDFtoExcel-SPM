//
//  XLSXGenerator.swift
//  PDFtoExcel
//
//  Real Excel XLSX file generation using Office Open XML format
//  Created by Assistant on 11/07/25.
//

import Foundation
import ZIPFoundation
import OSLog

// MARK: - XLSX Generator

class XLSXGenerator {
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "XLSXGenerator")
    
    // MARK: - Main Generation Method
    
    func generateXLSX(
        tables: [TableData],
        withDataTypes types: [[DetectedDataType]]? = nil,
        to url: URL,
        options: XLSXOptions = XLSXOptions()
    ) throws {
        
        // Create temporary directory for XLSX structure
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Cleanup temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create XLSX directory structure
        try createDirectoryStructure(at: tempDir)
        
        // Generate XML files
        try generateRelationships(at: tempDir)
        try generateApp(at: tempDir)
        try generateCore(at: tempDir, fileName: url.deletingPathExtension().lastPathComponent)
        let sheetNames = options.separateByPage ? sheetNames(for: tables) : ["Sheet1"]
        try generateContentTypes(at: tempDir, sheetCount: sheetNames.count)
        try generateWorkbook(at: tempDir, names: sheetNames)
        try generateWorkbookRels(at: tempDir, sheetCount: sheetNames.count)
        try generateStyles(at: tempDir, options: options)
        try generateSharedStrings(from: tables, at: tempDir)
        
        // Generate worksheets
        if options.separateByPage {
            // One sheet per table/page
            for (index, table) in tables.enumerated() {
                let dataTypes = types?[safe: index]
                try generateWorksheet(
                    table: table,
                    dataTypes: dataTypes,
                    index: index + 1,
                    at: tempDir,
                    options: options
                )
            }
        } else {
            // Combine all tables into one sheet
            let combinedTable = combineTables(tables)
            try generateWorksheet(
                table: combinedTable,
                dataTypes: nil,
                index: 1,
                at: tempDir,
                options: options
            )
        }
        
        // Create ZIP archive
        try createZipArchive(from: tempDir, to: url, sheetCount: sheetNames.count)
        
        logger.info("Successfully generated XLSX file at \(url.path)")
    }
    
    // MARK: - Directory Structure
    
    private func createDirectoryStructure(at baseURL: URL) throws {
        let directories = [
            "_rels",
            "docProps",
            "xl",
            "xl/_rels",
            "xl/theme",
            "xl/worksheets"
        ]
        
        for dir in directories {
            let dirURL = baseURL.appendingPathComponent(dir, isDirectory: true)
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Content Types
    
    /// A sheet name per table: the page it came from, made unique where a page
    /// yields more than one table. Excel refuses a workbook whose sheets share
    /// a name, and two tables on one page is ordinary.
    private func sheetNames(for tables: [TableData]) -> [String] {
        var seen: [Int: Int] = [:]
        
        return tables.map { table in
            seen[table.pageNumber, default: 0] += 1
            let occurrence = seen[table.pageNumber] ?? 1
            return occurrence == 1
                ? "Page \(table.pageNumber)"
                : "Page \(table.pageNumber) (\(occurrence))"
        }
    }
    
    private func generateContentTypes(at baseURL: URL, sheetCount: Int) throws {
        // Every worksheet needs its own override. Declaring only the first left
        // the rest of a multi-page workbook untyped, which readers reject.
        let worksheets = (1...max(sheetCount, 1)).map { index in
            """
                <Override PartName="/xl/worksheets/sheet\(index).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            """
        }.joined(separator: "\n")
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        \(worksheets)
            <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
            <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
        
        let url = baseURL.appendingPathComponent("[Content_Types].xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Relationships
    
    private func generateRelationships(at baseURL: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
            <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
        
        let url = baseURL.appendingPathComponent("_rels/.rels")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - App Properties
    
    private func generateApp(at baseURL: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
            <Application>PDFtoExcel Converter</Application>
            <AppVersion>1.0</AppVersion>
            <Company>PDFtoExcel</Company>
        </Properties>
        """
        
        let url = baseURL.appendingPathComponent("docProps/app.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Core Properties
    
    private func generateCore(at baseURL: URL, fileName: String) throws {
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <dc:title>\(fileName)</dc:title>
            <dc:creator>PDFtoExcel Converter</dc:creator>
            <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
            <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
        
        let url = baseURL.appendingPathComponent("docProps/core.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Workbook
    
    private func generateWorkbook(at baseURL: URL, names: [String]) throws {
        var sheets = ""
        for (index, name) in names.enumerated() {
            sheets += """
                <sheet name="\(name.xmlEscaped)" sheetId="\(index + 1)" r:id="rId\(index + 1)"/>
            """
        }
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
                \(sheets)
            </sheets>
        </workbook>
        """
        
        let url = baseURL.appendingPathComponent("xl/workbook.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Workbook Relationships
    
    private func generateWorkbookRels(at baseURL: URL, sheetCount: Int) throws {
        var relationships = """
            <Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            <Relationship Id="sharedStrings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        """
        
        for i in 1...max(sheetCount, 1) {
            relationships += """
                <Relationship Id="rId\(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(i).xml"/>
            """
        }
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            \(relationships)
        </Relationships>
        """
        
        let url = baseURL.appendingPathComponent("xl/_rels/workbook.xml.rels")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Styles
    
    private func generateStyles(at baseURL: URL, options: XLSXOptions) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <numFmts count="5">
                <numFmt numFmtId="164" formatCode="General"/>
                <numFmt numFmtId="165" formatCode="0"/>
                <numFmt numFmtId="166" formatCode="0.00"/>
                <numFmt numFmtId="167" formatCode="$#,##0.00"/>
                <numFmt numFmtId="168" formatCode="0.00%"/>
            </numFmts>
            <fonts count="3">
                <font>
                    <sz val="11"/>
                    <name val="Calibri"/>
                </font>
                <font>
                    <b/>
                    <sz val="11"/>
                    <name val="Calibri"/>
                </font>
                <font>
                    <i/>
                    <sz val="10"/>
                    <color rgb="FF666666"/>
                    <name val="Calibri"/>
                </font>
            </fonts>
            <fills count="3">
                <fill>
                    <patternFill patternType="none"/>
                </fill>
                <fill>
                    <patternFill patternType="gray125"/>
                </fill>
                <fill>
                    <patternFill patternType="solid">
                        <fgColor rgb="FFE0E0E0"/>
                    </patternFill>
                </fill>
            </fills>
            <borders count="2">
                <border>
                    <left/>
                    <right/>
                    <top/>
                    <bottom/>
                    <diagonal/>
                </border>
                <border>
                    <left style="thin">
                        <color rgb="FFB0B0B0"/>
                    </left>
                    <right style="thin">
                        <color rgb="FFB0B0B0"/>
                    </right>
                    <top style="thin">
                        <color rgb="FFB0B0B0"/>
                    </top>
                    <bottom style="thin">
                        <color rgb="FFB0B0B0"/>
                    </bottom>
                </border>
            </borders>
            <cellXfs count="10">
                <xf borderId="0" fillId="0" fontId="0" numFmtId="164"/>
                <xf borderId="1" fillId="2" fontId="1" numFmtId="164" applyBorder="1" applyFill="1" applyFont="1"/>
                <xf borderId="1" fillId="0" fontId="0" numFmtId="164" applyBorder="1"/>
                <xf borderId="1" fillId="0" fontId="0" numFmtId="165" applyBorder="1"/>
                <xf borderId="1" fillId="0" fontId="0" numFmtId="166" applyBorder="1"/>
                <xf borderId="1" fillId="0" fontId="0" numFmtId="167" applyBorder="1"/>
                <xf borderId="1" fillId="0" fontId="0" numFmtId="168" applyBorder="1"/>
                <xf borderId="0" fillId="0" fontId="2" numFmtId="164" applyFont="1"/>
                <xf borderId="1" fillId="0" fontId="1" numFmtId="164" applyBorder="1" applyFont="1"/>
                <xf borderId="1" fillId="2" fontId="1" numFmtId="164" applyBorder="1" applyFill="1" applyFont="1"/>
            </cellXfs>
        </styleSheet>
        """
        
        let url = baseURL.appendingPathComponent("xl/styles.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Shared Strings
    
    private func generateSharedStrings(from tables: [TableData], at baseURL: URL) throws {
        var uniqueStrings: [String] = []
        var stringMap: [String: Int] = [:]
        
        // Collect all unique strings
        for table in tables {
            for row in table.enhancedCleanedRows {
                for cell in row {
                    if !cell.isEmpty && stringMap[cell] == nil {
                        stringMap[cell] = uniqueStrings.count
                        uniqueStrings.append(cell)
                    }
                }
            }
        }
        
        var items = ""
        for string in uniqueStrings {
            items += """
                <si><t>\(string.xmlEscaped)</t></si>
            """
        }
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(uniqueStrings.count)" uniqueCount="\(uniqueStrings.count)">
            \(items)
        </sst>
        """
        
        let url = baseURL.appendingPathComponent("xl/sharedStrings.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Worksheet Generation
    
    private func generateWorksheet(
        table: TableData,
        dataTypes: [DetectedDataType]?,
        index: Int,
        at baseURL: URL,
        options: XLSXOptions
    ) throws {
        
        var rows = ""
        let analyzer = TableStructureAnalyzer()
        let headerInfo = analyzer.detectHeaders(in: table)
        
        // A frozen pane split at row zero is not a split at all; leave the view
        // alone unless there is a header row to hold in place.
        let freezePane = options.freezeHeaders && headerInfo.hasHeader
            ? #"<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>"#
            : ""

        
        for (rowIndex, row) in table.enhancedCleanedRows.enumerated() {
            var cells = ""
            
            for (colIndex, cell) in row.enumerated() {
                let cellRef = columnLetter(colIndex) + "\(rowIndex + 1)"
                let dataType = dataTypes?[safe: colIndex] ?? .text
                
                // Determine style based on position and data type
                var styleIndex = 2  // Default with border
                
                if headerInfo.hasHeader && rowIndex == headerInfo.headerRow {
                    styleIndex = 1  // Header style (bold with background)
                } else {
                    switch dataType {
                    case .integer:
                        styleIndex = 3
                    case .decimal:
                        styleIndex = 4
                    case .currency:
                        styleIndex = 5
                    case .percentage:
                        styleIndex = 6
                    default:
                        styleIndex = 2
                    }
                }
                
                // Generate cell XML
                if let numericValue = numericValue(of: cell, as: dataType) {
                    // Numeric cell
                    cells += """
                        <c r="\(cellRef)" s="\(styleIndex)">
                            <v>\(numericValue)</v>
                        </c>
                    """
                } else if !cell.isEmpty {
                    // String cell (use shared strings)
                    cells += """
                        <c r="\(cellRef)" s="\(styleIndex)" t="inlineStr">
                            <is><t>\(cell.xmlEscaped)</t></is>
                        </c>
                    """
                } else {
                    // Empty cell with border
                    cells += """
                        <c r="\(cellRef)" s="\(styleIndex)"/>
                    """
                }
            }
            
            rows += """
                <row r="\(rowIndex + 1)">
                    \(cells)
                </row>
            """
        }
        
        // Calculate column widths
        var columnWidths = ""
        if options.autoSizeColumns {
            let widths = calculateColumnWidths(table)
            for (index, width) in widths.enumerated() {
                columnWidths += """
                    <col min="\(index + 1)" max="\(index + 1)" width="\(width)" customWidth="1"/>
                """
            }
        }
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <dimension ref="\(dimension(of: table))"/>
            <sheetViews>
                <sheetView tabSelected="\(index == 1 ? "1" : "0")" workbookViewId="0">
                    \(freezePane)
                </sheetView>
            </sheetViews>
            <cols>
                \(columnWidths)
            </cols>
            <sheetData>
                \(rows)
            </sheetData>
            <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
        </worksheet>
        """
        
        let url = baseURL.appendingPathComponent("xl/worksheets/sheet\(index).xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Helper Methods
    
    /// The number to store for a cell, or nil if it is not a figure.
    ///
    /// A percentage is stored as the fraction it stands for. Excel's percent
    /// formats scale by a hundred on the way to the screen, so storing the 12
    /// read off the page as-is showed the reader 1200%.
    private func numericValue(of cell: String, as type: DetectedDataType) -> Double? {
        let bare = cell
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        let stripped = String(bare.unicodeScalars.filter { $0.properties.generalCategory != .currencySymbol })
        
        guard let value = Double(stripped) else { return nil }
        return type == .percentage ? value / 100 : value
    }
    
    /// The range a sheet occupies, in A1 notation.
    private func dimension(of table: TableData) -> String {
        let rows = table.enhancedCleanedRows
        let columns = rows.map(\.count).max() ?? 0
        
        guard columns > 0, !rows.isEmpty else { return "A1" }
        return "A1:\(columnLetter(columns - 1))\(rows.count)"
    }
    
    private func combineTables(_ tables: [TableData]) -> TableData {
        var allRows: [[String]] = []
        
        for (index, table) in tables.enumerated() {
            if index > 0 {
                // Add separator
                allRows.append([""])
                allRows.append(["Page \(table.pageNumber)", "Confidence: \(String(format: "%.1f%%", table.confidence * 100))"])
                allRows.append([""])
            }
            
            allRows.append(contentsOf: table.enhancedCleanedRows)
        }
        
        let maxColumns = allRows.map { $0.count }.max() ?? 0
        
        return TableData(
            rows: allRows,
            columnCount: maxColumns,
            rowCount: allRows.count,
            confidence: tables.reduce(0) { $0 + $1.confidence } / Float(max(tables.count, 1)),
            pageNumber: 1
        )
    }
    
    private func calculateColumnWidths(_ table: TableData) -> [Double] {
        var maxWidths: [Double] = Array(repeating: 10.0, count: table.columnCount)
        
        for row in table.enhancedCleanedRows {
            for (index, cell) in row.enumerated() where index < maxWidths.count {
                let width = Double(cell.count) * 1.2 + 2.0
                maxWidths[index] = min(max(maxWidths[index], width), 50.0)
            }
        }
        
        return maxWidths
    }
    
    private func columnLetter(_ index: Int) -> String {
        var letter = ""
        var idx = index
        
        while idx >= 0 {
            letter = String(Character(UnicodeScalar(65 + idx % 26)!)) + letter
            idx = idx / 26 - 1
        }
        
        return letter
    }
    
    /// Package the staged parts as an OPC archive.
    ///
    /// Zipping the staging directory wholesale nested every part under that
    /// directory's temporary name, so nothing could find `/xl/workbook.xml` and
    /// no reader would open the result. The parts are added deliberately
    /// instead, content types first, as the package format requires.
    private func createZipArchive(from sourceURL: URL, to destinationURL: URL, sheetCount: Int) throws {
        let archive = try Archive(url: destinationURL, accessMode: .create)
        
        for part in packageParts(sheetCount: sheetCount) {
            try archive.addEntry(
                with: part,
                relativeTo: sourceURL,
                compressionMethod: .deflate
            )
        }
    }
    
    /// The parts this generator writes, in the order they belong in the package.
    private func packageParts(sheetCount: Int) -> [String] {
        var parts = [
            "[Content_Types].xml",
            "_rels/.rels",
            "docProps/app.xml",
            "docProps/core.xml",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/styles.xml",
            "xl/sharedStrings.xml"
        ]
        parts += (1...max(sheetCount, 1)).map { "xl/worksheets/sheet\($0).xml" }
        return parts
    }
}

// MARK: - Supporting Types

struct XLSXOptions {
    var separateByPage: Bool = true
    var includeConfidence: Bool = true
    var autoSizeColumns: Bool = true
    var freezeHeaders: Bool = true
    var applyBorders: Bool = true
    var highlightHeaders: Bool = true
}

extension String {
    var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
