//
//  DataTypeDetectorTests.swift
//  PDFtoExcelTests
//

import Testing
@testable import PDFtoExcel

@Suite("Column type detection")
struct DataTypeDetectorTests {
    let detector = DataTypeDetector()
    
    private func types(_ rows: [[String]]) -> [DetectedDataType] {
        detector.detectColumnTypes(table: TableData(
            rows: rows,
            columnCount: rows.map(\.count).max() ?? 0,
            rowCount: rows.count,
            confidence: 0.9,
            pageNumber: 1
        ))
    }
    
    @Test("Each column is typed from the values below its header")
    func typesColumns() {
        let detected = types([
            ["Item", "Qty", "Price", "Share", "Paid"],
            ["Bolt", "12", "$3.50", "12%", "yes"],
            ["Nut", "40", "$0.75", "40%", "no"],
            ["Screw", "7", "$1.25", "7%", "yes"],
        ])
        
        // The header row is typed along with the data, so a column needs its
        // values to outweigh it — seven tenths of the cells must agree.
        #expect(detected[1] == .integer)
        #expect(detected[2] == .currency)
        #expect(detected[3] == .percentage)
        #expect(detected[4] == .boolean)
    }
    
    @Test("A column of words is text")
    func wordsAreText() {
        let detected = types([
            ["Bolt", "Nut"],
            ["Screw", "Rivet"],
            ["Washer", "Pin"],
        ])
        
        #expect(detected == [.text, .text])
    }
    
    @Test("Decimals are distinguished from whole numbers")
    func decimalsAreNotIntegers() {
        let detected = types([
            ["3.50", "12"],
            ["0.75", "40"],
            ["1.25", "7"],
        ])
        
        #expect(detected == [.decimal, .integer])
    }
    
    @Test("A column of dates is recognized")
    func datesAreRecognized() {
        let detected = types([
            ["01/14/2025"],
            ["02/28/2025"],
            ["12/31/2024"],
        ])
        
        #expect(detected == [.date])
    }
    
    @Test("A column that is mostly text stays text despite a stray figure")
    func mixedColumnFallsBackToText() {
        let detected = types([
            ["Bolt"],
            ["Nut"],
            ["12"],
            ["Screw"],
        ])
        
        #expect(detected == [.text])
    }
    
    @Test("An empty table has no columns to type")
    func emptyTable() {
        #expect(types([]).isEmpty)
    }
    
    @Test("Currencies other than the dollar are recognized")
    func nonDollarCurrencies() {
        #expect(types([["€100"], ["€250"], ["€75"]]) == [.currency])
        #expect(types([["£100"], ["£250"], ["£75"]]) == [.currency])
        #expect(types([["¥100"], ["¥250"], ["¥75"]]) == [.currency])
        #expect(types([["₹100"], ["₹250"], ["₹75"]]) == [.currency])
    }
    
    @Test("A column of bare figures is not currency")
    func figuresAreNotCurrency() {
        #expect(types([["100"], ["250"], ["75"]]) == [.integer])
        #expect(types([["1.00"], ["2.50"], ["0.75"]]) == [.decimal])
    }
    
    @Test("An amount is read as currency whichever side its symbol sits")
    func symbolPosition() {
        #expect(types([["100 €"], ["250 €"], ["75 €"]]) == [.currency])
        #expect(types([["$100"], ["$250"], ["$75"]]) == [.currency])
    }
}
