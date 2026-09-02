//
//  DataTypeDetector.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 11/06/25.
//

import Foundation

enum DetectedDataType: String {
    case text
    case integer
    case decimal
    case currency
    case percentage
    case date
    case boolean
    
    var excelFormat: String {
        switch self {
        case .text: return "text"
        case .integer: return "0"
        case .decimal: return "0.00"
        case .currency: return "$#,##0.00"
        case .percentage: return "0.00%"
        case .date: return "MM/DD/YYYY"
        case .boolean: return "text"
        }
    }
}

class DataTypeDetector {
    private let dateFormatters = [
        "MM/dd/yyyy", "MM-dd-yyyy", "yyyy-MM-dd",
        "dd/MM/yyyy", "dd-MM-yyyy",
        "M/d/yy", "M/d/yyyy",
        "MMM d, yyyy", "MMMM d, yyyy",
        "dd.MM.yyyy", "yyyy.MM.dd"
    ]
    
    func detectColumnTypes(table: TableData) -> [DetectedDataType] {
        guard !table.rows.isEmpty else { return [] }
        
        let rows = table.cleanedRows.filter { !$0.allSatisfy { $0.isEmpty } }
        guard !rows.isEmpty else { return [] }
        
        let columnCount = rows.first?.count ?? 0
        var detectedTypes: [DetectedDataType] = []
        
        for colIndex in 0..<columnCount {
            let columnValues = rows
                .compactMap { $0.count > colIndex ? $0[colIndex] : nil }
                .filter { !$0.isEmpty }
            
            if columnValues.isEmpty {
                detectedTypes.append(.text)
            } else {
                let detectedType = detectType(for: columnValues)
                detectedTypes.append(detectedType)
            }
        }
        
        return detectedTypes
    }
    
    private func detectType(for values: [String]) -> DetectedDataType {
        let filledCount = values.count
        guard filledCount > 0 else { return .text }
        
        var typeScores: [DetectedDataType: Int] = [
            .text: 0,
            .integer: 0,
            .decimal: 0,
            .currency: 0,
            .percentage: 0,
            .date: 0,
            .boolean: 0
        ]
        
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            
            if isBoolean(trimmed) {
                typeScores[.boolean, default: 0] += 1
                continue
            }
            
            if isPercentage(trimmed) {
                typeScores[.percentage, default: 0] += 2
                continue
            }
            
            if isCurrency(trimmed) {
                typeScores[.currency, default: 0] += 2
                continue
            }
            
            if isInteger(trimmed) {
                typeScores[.integer, default: 0] += 1
                typeScores[.decimal, default: 0] += 1
                continue
            }
            
            if isDecimal(trimmed) {
                typeScores[.decimal, default: 0] += 1
                continue
            }
            
            if isDate(trimmed) {
                typeScores[.date, default: 0] += 1
                continue
            }
            
            typeScores[.text, default: 0] += 1
        }
        
        let threshold = Double(filledCount) * 0.7
        
        if typeScores[.currency, default: 0] >= Int(threshold) {
            return .currency
        }
        if typeScores[.percentage, default: 0] >= Int(threshold) {
            return .percentage
        }
        if typeScores[.date, default: 0] >= Int(threshold) {
            return .date
        }
        if typeScores[.boolean, default: 0] >= Int(threshold) {
            return .boolean
        }
        if typeScores[.integer, default: 0] >= Int(threshold) {
            return .integer
        }
        if typeScores[.decimal, default: 0] >= Int(threshold) {
            return .decimal
        }
        
        return .text
    }
    
    private func isBoolean(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["yes", "no", "true", "false", "on", "off", "y", "n"].contains(lower)
    }
    
    private func isPercentage(_ value: String) -> Bool {
        value.contains("%")
    }
    
    private func isCurrency(_ value: String) -> Bool {
        // Asked of Unicode rather than matched against a list of symbols. The
        // list this replaced had been written to the file double-encoded, so
        // every symbol in it but the dollar was mojibake and matched nothing a
        // page could contain; a category test cannot be corrupted that way, and
        // covers the currencies a hand-written list forgets.
        value.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
    }
    
    private func isInteger(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "-+"))
        return !trimmed.isEmpty && trimmed.allSatisfy { $0.isNumber }
    }
    
    private func isDecimal(_ value: String) -> Bool {
        var cleaned = value.replacingOccurrences(of: ",", with: "")
        cleaned = String(cleaned.unicodeScalars.filter { $0.properties.generalCategory != .currencySymbol })
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-+%"))
        
        let components = cleaned.split(separator: ".", maxSplits: 1)
        
        if components.count == 1 {
            return !components[0].isEmpty && components[0].allSatisfy { $0.isNumber }
        } else if components.count == 2 {
            return !components[0].isEmpty && 
                   !components[1].isEmpty &&
                   components[0].allSatisfy { $0.isNumber } &&
                   components[1].allSatisfy { $0.isNumber }
        }
        
        return false
    }
    
    private func isDate(_ value: String) -> Bool {
        for format in dateFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if formatter.date(from: value) != nil {
                return true
            }
        }
        return false
    }
}
