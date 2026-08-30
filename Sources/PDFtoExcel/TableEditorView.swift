//
//  TableEditorView.swift
//  PDFtoExcel
//
//  Pre-export table preview and editing interface
//  Allows users to review and edit detected tables before exporting
//

import SwiftUI
import OSLog

// MARK: - Preview Data Model

struct TablePreviewData: Identifiable {
    let id = UUID()
    var tables: [TableData]
    let originalURL: URL
    let outputFormat: String
}

// MARK: - Main Table Editor View

struct TableEditorView: View {
    @State private var editedTables: [TableData]
    @State private var selectedTableIndex = 0
    @State private var searchText = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingStats = false
    
    let previewData: TablePreviewData
    let onExport: ([TableData]) -> Void
    let onCancel: () -> Void
    
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "tableEditor")
    
    init(previewData: TablePreviewData, onExport: @escaping ([TableData]) -> Void, onCancel: @escaping () -> Void) {
        self.previewData = previewData
        self._editedTables = State(initialValue: previewData.tables)
        self.onExport = onExport
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content area
            HSplitView {
                // Left sidebar - table list
                tableListSidebar
                    .frame(minWidth: 200, maxWidth: 250)
                
                // Right content - table editor
                tableEditorView
                    .frame(minWidth: 500)
            }
            
            Divider()
            
            // Bottom action bar
            actionBar
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review & Edit Tables")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(previewData.originalURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stats button
            Button {
                showingStats.toggle()
            } label: {
                Label("\(editedTables.count) tables", systemImage: "chart.bar.doc.horizontal")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingStats) {
                statisticsView
                    .padding()
            }
        }
        .padding()
    }
    
    // MARK: - Table List Sidebar
    
    private var tableListSidebar: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search tables...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding()
            
            // Table list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(filteredTables.enumerated()), id: \.offset) { index, table in
                        TableListItem(
                            table: table,
                            index: index,
                            isSelected: selectedTableIndex == index,
                            onSelect: { selectedTableIndex = index },
                            onDelete: { deleteTable(at: index) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            
            // Add table button
            Button {
                addEmptyTable()
            } label: {
                Label("Add Empty Table", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    // MARK: - Table Editor
    
    private var tableEditorView: some View {
        VStack(spacing: 0) {
            // Table header with controls
            tableControlsHeader
            
            Divider()
            
            // Table grid
            if selectedTableIndex < editedTables.count {
                TableGridEditor(
                    table: $editedTables[selectedTableIndex],
                    searchText: searchText
                )
            } else {
                emptySelectionView
            }
        }
    }
    
    private var tableControlsHeader: some View {
        HStack {
            // Table info
            if selectedTableIndex < editedTables.count {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Table \(selectedTableIndex + 1)")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label("\(editedTables[selectedTableIndex].rows.count) rows", systemImage: "tablecells")
                        Label("\(editedTables[selectedTableIndex].columnCount) cols", systemImage: "rectangle.grid.1x2")
                        Label("Page \(editedTables[selectedTableIndex].pageNumber)", systemImage: "doc.text")
                        
                        // Confidence indicator
                        HStack(spacing: 4) {
                            Image(systemName: confidenceIcon(editedTables[selectedTableIndex].confidence))
                                .foregroundColor(confidenceColor(editedTables[selectedTableIndex].confidence))
                            Text("\(Int(editedTables[selectedTableIndex].confidence * 100))%")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Table actions
            Menu {
                Button {
                    addRow()
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
                
                Button {
                    addColumn()
                } label: {
                    Label("Add Column", systemImage: "plus")
                }
                
                Divider()
                
                Button {
                    duplicateTable()
                } label: {
                    Label("Duplicate Table", systemImage: "doc.on.doc")
                }
                
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Table", systemImage: "trash")
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .confirmationDialog(
            "Delete this table?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteTable(at: selectedTableIndex)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var emptySelectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No table selected")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Select a table from the sidebar to edit")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack {
            // Help text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Double-click cells to edit â€¢ Right-click for more options")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape)
            
            Button {
                exportTables()
            } label: {
                Label("Export as \(previewData.outputFormat.uppercased())", systemImage: "arrow.down.doc")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(editedTables.isEmpty)
        }
        .padding()
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            Divider()
            
            StatRow(label: "Total Tables", value: "\(editedTables.count)")
            StatRow(label: "Total Rows", value: "\(totalRows)")
            StatRow(label: "Total Cells", value: "\(totalCells)")
            StatRow(label: "Avg. Confidence", value: "\(Int(averageConfidence * 100))%")
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Pages with Tables")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(pagesWithTables)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .frame(width: 250)
    }
    
    // MARK: - Helper Functions
    
    private var filteredTables: [TableData] {
        guard !searchText.isEmpty else { return editedTables }
        
        return editedTables.enumerated().compactMap { index, table in
            let matchesIndex = "table \(index + 1)".localizedCaseInsensitiveContains(searchText)
            let matchesPage = "page \(table.pageNumber)".localizedCaseInsensitiveContains(searchText)
            let matchesContent = table.rows.contains { row in
                row.contains { cell in
                    cell.localizedCaseInsensitiveContains(searchText)
                }
            }
            
            return matchesIndex || matchesPage || matchesContent ? table : nil
        }
    }
    
    private func addRow() {
        guard selectedTableIndex < editedTables.count else { return }
        let columnCount = editedTables[selectedTableIndex].columnCount
        let newRow = Array(repeating: "", count: columnCount)
        editedTables[selectedTableIndex].rows.append(newRow)
        logger.info("Added row to table \(selectedTableIndex + 1)")
    }
    
    private func addColumn() {
        guard selectedTableIndex < editedTables.count else { return }
        for rowIndex in 0..<editedTables[selectedTableIndex].rows.count {
            editedTables[selectedTableIndex].rows[rowIndex].append("")
        }
        logger.info("Added column to table \(selectedTableIndex + 1)")
    }
    
    private func deleteTable(at index: Int) {
        guard index < editedTables.count else { return }
        editedTables.remove(at: index)
        if selectedTableIndex >= editedTables.count && !editedTables.isEmpty {
            selectedTableIndex = editedTables.count - 1
        }
        logger.info("Deleted table at index \(index)")
    }
    
    private func addEmptyTable() {
        let newTable = TableData(
            rows: [["", "", ""], ["", "", ""], ["", "", ""]],
            columnCount: 3,
            rowCount: 3,
            confidence: 1.0,
            pageNumber: editedTables.last?.pageNumber ?? 1
        )
        editedTables.append(newTable)
        selectedTableIndex = editedTables.count - 1
        logger.info("Added empty table")
    }
    
    private func duplicateTable() {
        guard selectedTableIndex < editedTables.count else { return }
        let duplicate = editedTables[selectedTableIndex]
        editedTables.insert(duplicate, at: selectedTableIndex + 1)
        selectedTableIndex += 1
        logger.info("Duplicated table \(selectedTableIndex)")
    }
    
    private func exportTables() {
        logger.info("Exporting \(editedTables.count) tables")
        onExport(editedTables)
    }
    
    // MARK: - Computed Properties
    
    private var totalRows: Int {
        editedTables.reduce(0) { $0 + $1.rows.count }
    }
    
    private var totalCells: Int {
        editedTables.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.count } }
    }
    
    private var averageConfidence: Float {
        guard !editedTables.isEmpty else { return 0 }
        let sum = editedTables.reduce(Float(0)) { $0 + $1.confidence }
        return sum / Float(editedTables.count)
    }
    
    private var pagesWithTables: String {
        let pages = Set(editedTables.map { $0.pageNumber }).sorted()
        if pages.count <= 5 {
            return pages.map(String.init).joined(separator: ", ")
        } else {
            let first = pages.prefix(3).map(String.init).joined(separator: ", ")
            return "\(first), ... \(pages.last!)"
        }
    }
    
    private func confidenceIcon(_ confidence: Float) -> String {
        switch confidence {
        case 0.8...1.0: return "checkmark.circle.fill"
        case 0.5..<0.8: return "exclamationmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.5..<0.8: return .orange
        default: return .red
        }
    }
}

// MARK: - Table List Item

struct TableListItem: View {
    let table: TableData
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Table \(index + 1)")
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    Spacer()
                    
                    // Confidence badge
                    confidenceBadge
                }
                
                HStack(spacing: 8) {
                    Label("\(table.rows.count)Ã—\(table.columnCount)", systemImage: "tablecells")
                    Text("â€¢")
                    Label("P\(table.pageNumber)", systemImage: "doc.text")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private var confidenceBadge: some View {
        let confidence = table.confidence
        let color: Color
        let icon: String
        
        switch confidence {
        case 0.8...1.0:
            color = .green
            icon = "checkmark.circle.fill"
        case 0.5..<0.8:
            color = .orange
            icon = "exclamationmark.circle.fill"
        default:
            color = .red
            icon = "xmark.circle.fill"
        }
        
        return HStack(spacing: 2) {
            Image(systemName: icon)
            Text("\(Int(confidence * 100))%")
        }
        .font(.caption2)
        .foregroundColor(color)
    }
}

// MARK: - Table Grid Editor

struct TableGridEditor: View {
    @Binding var table: TableData
    let searchText: String
    
    @State private var editingCell: CellPosition?
    @State private var hoveredCell: CellPosition?
    
    struct CellPosition: Equatable {
        let row: Int
        let col: Int
    }
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                ForEach(0..<table.rows.count, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        // Row number
                        Text("\(rowIndex + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                            .frame(height: 32)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .border(Color.gray.opacity(0.2))
                        
                        // Cells
                        ForEach(0..<table.rows[rowIndex].count, id: \.self) { colIndex in
                            EditableCell(
                                text: $table.rows[rowIndex][colIndex],
                                position: CellPosition(row: rowIndex, col: colIndex),
                                isHeader: rowIndex == 0,
                                isEditing: editingCell == CellPosition(row: rowIndex, col: colIndex),
                                isHovered: hoveredCell == CellPosition(row: rowIndex, col: colIndex),
                                isHighlighted: isHighlighted(rowIndex: rowIndex, colIndex: colIndex),
                                onStartEdit: {
                                    editingCell = CellPosition(row: rowIndex, col: colIndex)
                                },
                                onEndEdit: {
                                    editingCell = nil
                                },
                                onHover: { isHovered in
                                    hoveredCell = isHovered ? CellPosition(row: rowIndex, col: colIndex) : nil
                                }
                            )
                        }
                    }
                }
                
                // Column headers (at bottom for reference)
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 40)
                    
                    ForEach(0..<(table.rows.first?.count ?? 0), id: \.self) { colIndex in
                        Text(columnLabel(colIndex))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 120, height: 24)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .border(Color.gray.opacity(0.2))
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func isHighlighted(rowIndex: Int, colIndex: Int) -> Bool {
        guard !searchText.isEmpty else { return false }
        return table.rows[rowIndex][colIndex].localizedCaseInsensitiveContains(searchText)
    }
    
    private func columnLabel(_ index: Int) -> String {
        var label = ""
        var num = index
        while num >= 0 {
            label = String(UnicodeScalar(65 + (num % 26))!) + label
            num = num / 26 - 1
            if num < 0 { break }
        }
        return label
    }
}

// MARK: - Editable Cell

struct EditableCell: View {
    @Binding var text: String
    let position: TableGridEditor.CellPosition
    let isHeader: Bool
    let isEditing: Bool
    let isHovered: Bool
    let isHighlighted: Bool
    let onStartEdit: () -> Void
    let onEndEdit: () -> Void
    let onHover: (Bool) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(backgroundColor)
                .border(borderColor, width: isEditing ? 2 : 1)
            
            // Content
            if isEditing {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .padding(4)
                    .onSubmit {
                        onEndEdit()
                    }
            } else {
                Text(text.isEmpty ? " " : text)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .font(isHeader ? .body.weight(.semibold) : .body)
                    .foregroundColor(isHeader ? .primary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onStartEdit()
                    }
            }
        }
        .frame(width: 120, minHeight: 32)
        .onHover { hovering in
            onHover(hovering)
        }
        .onChange(of: isEditing) { _, newValue in
            isFocused = newValue
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            
            Button("Paste") {
                if let string = NSPasteboard.general.string(forType: .string) {
                    text = string
                }
            }
            
            Button("Clear") {
                text = ""
            }
        }
    }
    
    private var backgroundColor: Color {
        if isHighlighted {
            return .yellow.opacity(0.3)
        } else if isEditing {
            return .white
        } else if isHovered {
            return Color.accentColor.opacity(0.1)
        } else if isHeader {
            return Color.blue.opacity(0.1)
        } else {
            return Color(nsColor: .textBackgroundColor)
        }
    }
    
    private var borderColor: Color {
        if isEditing {
            return .accentColor
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleTables = [
        TableData(
            rows: [
                ["Name", "Age", "City"],
                ["John", "30", "NYC"],
                ["Jane", "25", "LA"]
            ],
            columnCount: 3,
            rowCount: 3,
            confidence: 0.95,
            pageNumber: 1
        ),
        TableData(
            rows: [
                ["Product", "Price", "Quantity"],
                ["Widget", "$10", "100"],
                ["Gadget", "$25", "50"]
            ],
            columnCount: 3,
            rowCount: 3,
            confidence: 0.85,
            pageNumber: 2
        )
    ]
    
    let previewData = TablePreviewData(
        tables: sampleTables,
        originalURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
        outputFormat: "xlsx"
    )
    
    return TableEditorView(
        previewData: previewData,
        onExport: { tables in
            print("Exporting \(tables.count) tables")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
