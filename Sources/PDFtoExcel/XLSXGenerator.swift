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
        try generateContentTypes(at: tempDir)
        try generateRelationships(at: tempDir)
        try generateApp(at: tempDir)
        try generateCore(at: tempDir, fileName: url.deletingPathExtension().lastPathComponent)
        try generateWorkbook(at: tempDir, sheetCount: options.separateByPage ? tables.count : 1)
        try generateWorkbookRels(at: tempDir, sheetCount: options.separateByPage ? tables.count : 1)
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
        try createZipArchive(from: tempDir, to: url)
        
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
    
    private func generateContentTypes(at baseURL: URL) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
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
    
    private func generateWorkbook(at baseURL: URL, sheetCount: Int) throws {
        var sheets = ""
        for i in 1...max(sheetCount, 1) {
            let sheetName = sheetCount > 1 ? "Page \(i)" : "Sheet1"
            sheets += """
                <sheet name="\(sheetName.xmlEscaped)" sheetId="\(i)" r:id="rId\(i)"/>
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
                if let numericValue = Double(cell.replacingOccurrences(of: ",", with: "")
                                                  .replacingOccurrences(of: "$", with: "")
                                                  .replacingOccurrences(of: "%", with: "")) {
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
            <dimension ref="A1:\(columnLetter(table.columnCount - 1))\(table.rowCount)"/>
            <sheetViews>
                <sheetView tabSelected="\(index == 1 ? "1" : "0")" workbookViewId="0">
                    <pane ySplit="\(headerInfo.hasHeader ? "1" : "0")" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
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
    
    private func createZipArchive(from sourceURL: URL, to destinationURL: URL) throws {
        // Use ZIPFoundation to create the archive
        try FileManager.default.zipItem(at: sourceURL, to: destinationURL)
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

// MARK: - Integration Helper

extension PDFToExcelConverter {
    
    /// Generate real XLSX file instead of renamed CSV
    func generateRealXLSX(tables: [TableData], originalURL: URL, options: XLSXOptions = XLSXOptions()) throws -> URL {
        // Determine output directory
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputDir = documents.appendingPathComponent("PDFtoExcel", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let baseName = originalURL.deletingPathExtension().lastPathComponent + "_excel"
        var outputURL = outputDir.appendingPathComponent(baseName).appendingPathExtension("xlsx")
        
        // Avoid overwriting
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let candidateName = "\(baseName) (\(counter))"
            outputURL = outputDir.appendingPathComponent(candidateName).appendingPathExtension("xlsx")
            counter += 1
        }
        
        // Detect data types
        let detector = DataTypeDetector()
        let dataTypes = tables.map { detector.detectColumnTypes(table: $0) }
        
        // Generate XLSX
        let generator = XLSXGenerator()
        try generator.generateXLSX(
            tables: tables,
            withDataTypes: dataTypes,
            to: outputURL,
            options: options
        )
        
        return outputURL
    }
}
