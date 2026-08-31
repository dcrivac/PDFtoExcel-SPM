//
//  ProcessingViews.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/15/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Processing Queue View

struct SimpleProcessingQueueView: View {
    @ObservedObject var fileManager: FileProcessingManager
    @State private var showingFilePicker = false
    @State private var dragIsActive = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ProcessingHeaderView(
                fileManager: fileManager,
                showingFilePicker: $showingFilePicker
            )
            
            // Content
            if fileManager.processingQueue.isEmpty && !fileManager.isProcessing {
                ProcessingDropZoneView(
                    dragIsActive: $dragIsActive,
                    showingFilePicker: $showingFilePicker,
                    onDrop: handleFileDrop
                )
            } else {
                ProcessingListView(fileManager: fileManager)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }
    
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let urlProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !urlProviders.isEmpty else { return false }
        
        // The drop is accepted up front: the handler runs on the main thread, so
        // it cannot block waiting to find out which of these are really PDFs.
        Task { @MainActor in
            var urls: [URL] = []
            for provider in urlProviders {
                guard let url = await provider.loadURL(),
                      url.pathExtension.lowercased() == "pdf" else { continue }
                urls.append(url)
            }
            
            guard !urls.isEmpty else { return }
            await fileManager.addFiles(urls)
        }
        return true
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await fileManager.addFiles(urls)
            }
        case .failure(let error):
            print("File import error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Processing Header

struct ProcessingHeaderView: View {
    @ObservedObject var fileManager: FileProcessingManager
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing Queue")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if fileManager.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            
                            Text("Processing files...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if !fileManager.processingQueue.isEmpty {
                        Text("\(fileManager.processingQueue.count) files in queue")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Add Files", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(fileManager.isProcessing)
                        
                        if !fileManager.processingQueue.isEmpty {
                            Button {
                                fileManager.clearQueue()
                            } label: {
                                Label("Clear Queue", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(fileManager.isProcessing)
                        }
                    }
                }
            }
            
            // Overall progress
            if fileManager.isProcessing {
                VStack(spacing: 8) {
                    HStack {
                        Text("Overall Progress")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(fileManager.overallProgress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    
                    ProgressView(value: fileManager.overallProgress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 2.0)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}

// MARK: - Processing Drop Zone

struct ProcessingDropZoneView: View {
    @Binding var dragIsActive: Bool
    @Binding var showingFilePicker: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 20) {
                Image(systemName: dragIsActive ? "doc.badge.plus.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(dragIsActive ? .blue : .secondary)
                    .scaleEffect(dragIsActive ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: dragIsActive)
                
                VStack(spacing: 12) {
                    Text(dragIsActive ? "Drop PDF files here" : "Add PDFs to Processing Queue")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(dragIsActive ? .blue : .primary)
                    
                    Text("Files will be validated and queued for batch processing")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button {
                showingFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Add PDF Files")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .scaleEffect(dragIsActive ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: dragIsActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .stroke(
                    dragIsActive ? .blue : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: dragIsActive ? [10, 5] : [])
                )
                .animation(.easeInOut(duration: 0.3), value: dragIsActive)
        }
        .padding(24)
        .onDrop(of: [.fileURL], isTargeted: $dragIsActive) { providers in
            onDrop(providers)
        }
    }
}

// MARK: - Processing List

struct ProcessingListView: View {
    @ObservedObject var fileManager: FileProcessingManager
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(fileManager.processingQueue) { job in
                    SimpleProcessingJobRow(
                        job: job,
                        onRetry: { job in
                            Task {
                                await fileManager.retryFailedJob(job)
                            }
                        },
                        onRemove: { job in
                            fileManager.removeJob(job)
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Processing Job Row

struct SimpleProcessingJobRow: View {
    let job: ProcessingJob
    let onRetry: (ProcessingJob) -> Void
    let onRemove: (ProcessingJob) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Status icon
            Image(systemName: job.status.icon)
                .font(.title2)
                .foregroundStyle(job.status.color)
                .frame(width: 24)
            
            // File info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(job.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(job.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(job.status.color)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if job.status == .processing {
                        Text("~\(job.estimatedTimeRemaining)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                
                // Progress bar for active jobs
                if job.status == .processing || job.status == .completed {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 1.5)
                }
                
                // Error message
                if let error = job.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            
            // Actions
            VStack(spacing: 4) {
                if job.status == .failed {
                    Button {
                        onRetry(job)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                
                if job.status != .processing {
                    Button {
                        onRemove(job)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(job.status.color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Completed Files View

struct CompletedFilesView: View {
    @ObservedObject var fileManager: FileProcessingManager
    @State private var selectedFiles: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            CompletedFilesHeaderView(
                fileManager: fileManager,
                selectedFiles: $selectedFiles
            )
            
            // Content
            if fileManager.completedJobs.isEmpty {
                CompletedFilesEmptyView()
            } else {
                CompletedFilesListView(
                    fileManager: fileManager,
                    selectedFiles: $selectedFiles
                )
            }
        }
    }
}

struct CompletedFilesHeaderView: View {
    @ObservedObject var fileManager: FileProcessingManager
    @Binding var selectedFiles: Set<UUID>
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed Files")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(fileManager.completedJobs.count) files processed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !fileManager.completedJobs.isEmpty {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                selectedFiles = selectedFiles.isEmpty ? 
                                    Set(fileManager.completedJobs.map { $0.id }) : []
                            } label: {
                                Text(selectedFiles.isEmpty ? "Select All" : "Deselect All")
                            }
                            .buttonStyle(.bordered)
                            
                            if !selectedFiles.isEmpty {
                                Button {
                                    // Handle bulk actions
                                } label: {
                                    Label("Actions", systemImage: "ellipsis.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            
            // Processing stats
            if fileManager.processingStats.totalFiles > 0 {
                ProcessingStatsView(stats: fileManager.processingStats)
            }
        }
        .padding()
    }
}

struct ProcessingStatsView: View {
    let stats: ProcessingStats
    
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 16) {
                StatCard(
                    title: "Success Rate",
                    value: "\(Int(stats.successRate * 100))%",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                StatCard(
                    title: "Avg Time",
                    value: "\(Int(stats.averageTimePerFile))s",
                    icon: "clock.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Total Files",
                    value: "\(stats.totalFiles)",
                    icon: "doc.fill",
                    color: .orange
                )
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct CompletedFilesEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text("No completed files yet")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("Files will appear here after processing")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompletedFilesListView: View {
    @ObservedObject var fileManager: FileProcessingManager
    @Binding var selectedFiles: Set<UUID>
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(fileManager.completedJobs) { file in
                    CompletedFileRow(
                        file: file,
                        isSelected: selectedFiles.contains(file.id),
                        onSelect: { toggleSelection(file.id) },
                        onAction: { action in
                            handleFileAction(action, for: file)
                        }
                    )
                }
            }
            .padding()
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
            #if os(macOS)
            NSWorkspace.shared.open(file.outputURL)
            #else
            // TODO: Provide platform-specific open handling
            #endif
        case .reveal:
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([file.outputURL])
            #else
            // TODO: Provide platform-specific reveal handling
            #endif
        case .delete:
            // Remove from completed files
            if let index = fileManager.completedJobs.firstIndex(where: { $0.id == file.id }) {
                fileManager.completedJobs.remove(at: index)
                selectedFiles.remove(file.id)
                try? FileManager.default.removeItem(at: file.outputURL)
            }
        }
    }
}

struct CompletedFileRow: View {
    let file: ProcessedFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onAction: (FileAction) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            
            // File icon
            Image(systemName: "doc.richtext.fill")
                .font(.title2)
                .foregroundStyle(.green.gradient)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label("\(file.pageCount)", systemImage: "doc.plaintext")
                    Label("\(file.tablesFound)", systemImage: "tablecells")
                    Label(file.formattedFileSize, systemImage: "externaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("Processed \(file.processedDate, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Actions
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    #if os(macOS)
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
                    #endif
                    
                    Button {
                        onAction(.delete)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AnyShapeStyle(Color.blue.opacity(0.1)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? .blue : Color.clear, lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

