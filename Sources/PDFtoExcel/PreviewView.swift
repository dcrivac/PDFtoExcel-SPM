//
//  PreviewView.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 11/06/25.
//

import SwiftUI
import PDFKit

struct PreviewView: View {
    let file: ProcessedFile
    @State private var showingPDFPreview = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Toggle buttons
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPDFPreview = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.richtext.fill")
                        Text("Original PDF")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(showingPDFPreview ? Color.blue : Color.clear)
                    .foregroundColor(showingPDFPreview ? .white : .primary)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 40)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingPDFPreview = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "tablecells.fill")
                        Text("Extracted Table")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(!showingPDFPreview ? Color.green : Color.clear)
                    .foregroundColor(!showingPDFPreview ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content area
            ZStack {
                if showingPDFPreview {
                    PDFPreviewView(fileURL: file.originalURL)
                        .transition(.opacity)
                } else {
                    TablePreviewView(fileURL: file.outputURL)
                        .transition(.opacity)
                }
            }
        }
    }
}

struct PDFPreviewView: View {
    let fileURL: URL
    @State private var pdfDocument: PDFDocument?
    
    var body: some View {
        VStack {
            if let pdfDocument = pdfDocument {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<pdfDocument.pageCount, id: \.self) { index in
                            if let page = pdfDocument.page(at: index) {
                                PDFPageView(page: page, pageNumber: index + 1)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading PDF preview...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadPDF()
        }
    }
    
    private func loadPDF() {
        pdfDocument = PDFDocument(url: fileURL)
    }
}

struct PDFPageView: View {
    let page: PDFPage
    let pageNumber: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Page \(pageNumber)")
                .font(.headline)
                .fontWeight(.semibold)
            
            Image(nsImage: page.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(.quaternary)
                .cornerRadius(8)
        }
    }
}

struct TablePreviewView: View {
    let fileURL: URL
    @State private var tableContent: [[String]] = []
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        VStack {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading extracted data...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tableContent.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    
                    Text("No table data to display")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<tableContent.count, id: \.self) { rowIndex in
                            HStack(spacing: 0) {
                                ForEach(0..<tableContent[rowIndex].count, id: \.self) { colIndex in
                                    Text(tableContent[rowIndex][colIndex])
                                        .font(.caption)
                                        .lineLimit(2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 80)
                                        .background(rowIndex == 0 ? Color.blue.opacity(0.2) : Color.clear)
                                        .border(Color.separator, width: 1)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            loadTableData()
        }
    }
    
    private func loadTableData() {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let rows = content.split(separator: "\n").map { String($0) }
            tableContent = rows.map { row in
                row.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            isLoading = false
        } catch {
            self.error = "Failed to load table data: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

#Preview {
    PreviewView(file: ProcessedFile(
        originalURL: URL(fileURLWithPath: "/test.pdf"),
        outputURL: URL(fileURLWithPath: "/test.csv"),
        fileName: "test",
        pageCount: 1,
        tablesFound: 1,
        processedDate: Date(),
        fileSize: 1000
    ))
}
