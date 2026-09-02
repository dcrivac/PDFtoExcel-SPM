//
//  ScanCorpusTests.swift
//  PDFtoExcelTests
//
//  End-to-end cover for the Vision boundary, run against whatever scans are
//  sitting in the local corpus.
//

import Foundation
import PDFKit
import Testing
@testable import PDFtoExcel

/// The scan corpus is large and local-only, so it is not in the repository and
/// these tests skip when it is absent.
struct ScanCorpus {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PDFtoExcelTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("pdf_test_files")
    
    static var files: [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return (contents ?? []).filter { $0.pathExtension == "pdf" }.sorted { $0.path < $1.path }
    }
    
    static var isAvailable: Bool { !files.isEmpty }
}

@Suite("Scan corpus", .enabled(if: ScanCorpus.isAvailable, "no local scan corpus"))
struct ScanCorpusTests {
    @Test("A scanned page still comes back as a table of several columns")
    @MainActor
    func readsAScan() async throws {
        let url = try #require(ScanCorpus.files.first)
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        
        let tables = try await PDFToExcelConverter()
            .extractTablesFromPage(page, pageNumber: 1, accuracy: .accurate)
        
        #expect(!tables.isEmpty)
        #expect(tables.contains { $0.columnCount >= 2 })
        #expect(tables.allSatisfy { !$0.isEmpty })
    }
}
