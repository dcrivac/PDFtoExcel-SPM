//
//  ContentView.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/14/25.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var converter = PDFToExcelConverter()
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var showingSettings = false
    @State private var alertMessage = ""
    @State private var dragIsActive = false
    @State private var selectedFiles: Set<UUID> = []
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(converter: converter,
                        showingSettings: $showingSettings,
                        selectedFiles: $selectedFiles)
        } detail: {
            // Main content
            MainContentView(
                converter: converter,
                showingFilePicker: $showingFilePicker,
                dragIsActive: $dragIsActive,
                selectedFiles: $selectedFiles
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(id: "main-toolbar") {
            ToolbarItem(id: "settings", placement: .primaryAction) {
                Button {
                    showingSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            
            ToolbarItem(id: "clear", placement: .primaryAction) {
                Button {
                    withAnimation(.smooth) {
                        converter.clearProcessedFiles()
                        selectedFiles.removeAll()
                    }
                } label: {
                    Label("Clear All", systemImage: "trash.fill")
                }
                .disabled(converter.processedFiles.isEmpty)
            }
            
            ToolbarSpacer(.flexible)
            
            ToolbarItem(id: "add-files", placement: .primaryAction) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Add Files", systemImage: "plus.circle.fill")
                }
                .disabled(converter.isProcessing)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await converter.convertFiles(urls)
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var converter: PDFToExcelConverter
    @Binding var showingSettings: Bool
    @Binding var selectedFiles: Set<UUID>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.richtext.fill")
                        .font(.title2)
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PDF to Excel")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Converter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Quick stats
                if !converter.processedFiles.isEmpty {
                    StatsCard(converter: converter)
                        .padding(.horizontal)
                }
            }
            
            // Files list
            if converter.processedFiles.isEmpty {
                EmptyStateView()
            } else {
                FilesList(
                    converter: converter,
                    selectedFiles: $selectedFiles
                )
            }
            
            Spacer()
        }
        .frame(minWidth: 280)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Main Content View

struct MainContentView: View {
    @ObservedObject var converter: PDFToExcelConverter
    @Binding var showingFilePicker: Bool
    @Binding var dragIsActive: Bool
    @Binding var selectedFiles: Set<UUID>
    
    var body: some View {
        VStack(spacing: 0) {
            if converter.processedFiles.isEmpty && !converter.isProcessing {
                // Drop zone
                DropZoneView(
                    dragIsActive: $dragIsActive,
                    showingFilePicker: $showingFilePicker,
                    onDrop: handleFileDrop
                )
            } else {
                // Main content area
                VStack(spacing: 24) {
                    if converter.isProcessing {
                        ProcessingView(converter: converter)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    
                    if !converter.processedFiles.isEmpty {
                        DetailView(
                            converter: converter,
                            selectedFiles: $selectedFiles
                        )
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let urls = providers.compactMap { provider -> URL? in
            var url: URL?
            let semaphore = DispatchSemaphore(value: 0)
            
            _ = provider.loadObject(ofClass: URL.self) { loadedURL, _ in
                url = loadedURL
                semaphore.signal()
            }
            
            semaphore.wait()
            return url?.pathExtension.lowercased() == "pdf" ? url : nil
        }
        
        if !urls.isEmpty {
            Task {
                await converter.convertFiles(urls)
            }
            return true
        }
        return false
    }
}

// MARK: - Drop Zone View

struct DropZoneView: View {
    @Binding var dragIsActive: Bool
    @Binding var showingFilePicker: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 20) {
                Image(systemName: dragIsActive ? "doc.badge.plus.fill" : "doc.richtext.fill.on.doc")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(dragIsActive ? .blue : .secondary)
                    .scaleEffect(dragIsActive ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: dragIsActive)
                
                VStack(spacing: 12) {
                    Text(dragIsActive ? "Drop PDF files here" : "Convert PDF Tables to Excel")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(dragIsActive ? .blue : .primary)
                    
                    Text("Drag and drop PDF files or click to browse")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button {
                showingFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2)
                    Text("Choose PDF Files")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor)
                )
            }
            .scaleEffect(dragIsActive ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: dragIsActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            dragIsActive ? Color.blue : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: dragIsActive ? [10, 5] : [])
                        )
                )
                .animation(.easeInOut(duration: 0.3), value: dragIsActive)
        }
        .padding(24)
        .onDrop(of: [.fileURL], isTargeted: $dragIsActive) { providers in
            onDrop(providers)
        }
    }
}

// MARK: - Supporting Views

struct StatsCard: View {
    @ObservedObject var converter: PDFToExcelConverter
    
    private var totalPages: Int {
        converter.processedFiles.reduce(0) { $0 + $1.pageCount }
    }
    
    private var totalTables: Int {
        converter.processedFiles.reduce(0) { $0 + $1.tablesFound }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            StatItem(
                value: "\(converter.processedFiles.count)",
                label: "Files",
                icon: "doc.fill"
            )
            
            StatItem(
                value: "\(totalPages)",
                label: "Pages",
                icon: "doc.plaintext"
            )
            
            StatItem(
                value: "\(totalTables)",
                label: "Tables",
                icon: "tablecells"
            )
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
        )
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No files processed yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Drag PDF files to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
}

struct ProcessingView: View {
    @ObservedObject var converter: PDFToExcelConverter
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing PDF files...")
                        .font(.headline)
                    
                    Text("\(Int(converter.progress * 100))% complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
            }
            
            ProgressView(value: converter.progress)
                .progressViewStyle(.linear)
                .scaleEffect(y: 2)
        }
        .padding(24)
    }
}

struct FilesList: View {
    @ObservedObject var converter: PDFToExcelConverter
    @Binding var selectedFiles: Set<UUID>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processed Files")
                    .font(.headline)
                
                Spacer()
                
                Text("\(converter.processedFiles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(converter.processedFiles) { file in
                        ProcessedFileRow(
                            file: file,
                            isSelected: selectedFiles.contains(file.id),
                            onSelect: { toggleSelection(file.id) },
                            onAction: { action in
                                handleFileAction(action, for: file)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        withAnimation(.spring(response: 0.3)) {
            if selectedFiles.contains(id) {
                selectedFiles.remove(id)
            } else {
                selectedFiles.insert(id)
            }
        }
    }
    
    private func handleFileAction(_ action: FileAction, for file: ProcessedFile) {
        switch action {
        case .open:
            converter.openOutputFile(file)
        case .reveal:
            converter.revealInFinder(file)
        case .delete:
            withAnimation(.smooth) {
                converter.removeProcessedFile(file)
                selectedFiles.remove(file.id)
            }
        }
    }
}

enum FileAction {
    case open, reveal, delete
}

struct ProcessedFileRow: View {
    let file: ProcessedFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onAction: (FileAction) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundStyle(isSelected ? .blue : .green)
                .frame(width: 24)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label("\(file.pageCount)", systemImage: "doc.plaintext")
                    Label("\(file.tablesFound)", systemImage: "tablecells")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button {
                    onAction(.open)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button {
                    onAction(.reveal)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button {
                    onAction(.delete)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct DetailView: View {
    @ObservedObject var converter: PDFToExcelConverter
    @Binding var selectedFiles: Set<UUID>
    
    var selectedFile: ProcessedFile? {
        guard selectedFiles.count == 1,
              let selectedId = selectedFiles.first else { return nil }
        return converter.processedFiles.first { $0.id == selectedId }
    }
    
    var body: some View {
        if let file = selectedFile {
            FileDetailView(file: file)
        } else if selectedFiles.count > 1 {
            MultipleSelectionView(count: selectedFiles.count)
        } else {
            SelectionPromptView()
        }
    }
}

struct FileDetailView: View {
    let file: ProcessedFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Image(systemName: "doc.richtext.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue.gradient)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.fileName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Processed \(file.processedDate, format: .relative(presentation: .named))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Action buttons
                #if os(macOS)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(file.outputURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([file.outputURL])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                #endif
            }
            
            // Statistics
            HStack(spacing: 16) {
                DetailStatCard(
                    title: "Pages",
                    value: "\(file.pageCount)",
                    icon: "doc.plaintext",
                    color: .blue
                )
                
                DetailStatCard(
                    title: "Tables Found",
                    value: "\(file.tablesFound)",
                    icon: "tablecells",
                    color: .green
                )
                
                DetailStatCard(
                    title: "File Size",
                    value: file.formattedFileSize,
                    icon: "doc.circle",
                    color: .orange
                )
            }
            
            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

struct DetailStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color.gradient)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
        )
    }
}

struct MultipleSelectionView: View {
    let count: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            
            Text("\(count) files selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a single file to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

struct SelectionPromptView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text("Select a file to view details")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
