//
//  ProcessingQueueView.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/15/25.
//

import SwiftUI
import QuickLook
import AppKit
import UniformTypeIdentifiers

// MARK: - Processing Queue View

struct ProcessingQueueView: View {
    @ObservedObject var processingManager: FileProcessingManager
    @State private var selectedJob: ProcessingJob?
    @State private var showingPreview = false
    @State private var previewURL: URL?
    
    var body: some View {
        NavigationSplitView {
            // Queue Sidebar
            QueueSidebarView(
                processingManager: processingManager,
                selectedJob: $selectedJob
            )
        } detail: {
            // Detail View
            if let job = selectedJob {
                JobDetailView(
                    job: job,
                    processingManager: processingManager,
                    showingPreview: $showingPreview,
                    previewURL: $previewURL
                )
            } else {
                QueueOverviewView(processingManager: processingManager)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .quickLookPreview($previewURL, in: showingPreview ? [previewURL].compactMap { $0 } : [])
        .toolbar(id: "processing-toolbar") {
            ToolbarItem(id: "clear-completed", placement: .primaryAction) {
                Button {
                    clearCompletedJobs()
                } label: {
                    Label("Clear Completed", systemImage: "checkmark.circle.2")
                }
                .disabled(processingManager.processingQueue.filter { $0.status == .completed }.isEmpty)
                .buttonStyle(.bordered)
            }
            
            ToolbarItem(id: "pause-resume", placement: .primaryAction) {
                Button {
                    toggleProcessing()
                } label: {
                    Label(
                        processingManager.isProcessing ? "Pause" : "Resume",
                        systemImage: processingManager.isProcessing ? "pause.circle" : "play.circle"
                    )
                }
                .disabled(processingManager.processingQueue.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            
            ToolbarSpacer(.flexible)
            
            ToolbarItem(id: "queue-add-files", placement: .primaryAction) {
                AddFilesButton(processingManager: processingManager)
            }
        }
    }
    
    private func clearCompletedJobs() {
        withAnimation(.smooth) {
            processingManager.processingQueue.removeAll { $0.status == .completed }
        }
    }
    
    private func toggleProcessing() {
        // Implementation would pause/resume processing
        // This is a placeholder for the functionality
    }
}

// MARK: - Queue Sidebar

struct QueueSidebarView: View {
    @ObservedObject var processingManager: FileProcessingManager
    @Binding var selectedJob: ProcessingJob?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Processing Queue")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("\(processingManager.processingQueue.count) files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Overall progress
                if processingManager.isProcessing {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Overall Progress")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(Int(processingManager.overallProgress * 100))%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: processingManager.overallProgress)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 2)
                            .tint(.blue)
                    }
                }
                
                // Quick stats
                ProcessingStatsCard(stats: processingManager.processingStats)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.top)
            
            // Queue list
            if processingManager.processingQueue.isEmpty {
                EmptyQueueView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(processingManager.processingQueue) { job in
                            ProcessingJobRow(
                                job: job,
                                isSelected: selectedJob?.id == job.id,
                                onSelect: { selectedJob = job },
                                onAction: { action in
                                    handleJobAction(action, for: job)
                                }
                            )
                        }
                    }
                }
                .padding(.top)
            }
            
            Spacer()
        }
        .frame(minWidth: 320)
        .background(.ultraThinMaterial)
    }
    
    private func handleJobAction(_ action: JobAction, for job: ProcessingJob) {
        Task {
            switch action {
            case .retry:
                await processingManager.retryFailedJob(job)
            case .remove:
                withAnimation(.smooth) {
                    processingManager.removeJob(job)
                    if selectedJob?.id == job.id {
                        selectedJob = nil
                    }
                }
            case .moveToTop:
                moveJobToTop(job)
            case .moveToBottom:
                moveJobToBottom(job)
            }
        }
    }
    
    private func moveJobToTop(_ job: ProcessingJob) {
        withAnimation(.smooth) {
            if let index = processingManager.processingQueue.firstIndex(where: { $0.id == job.id }) {
                let job = processingManager.processingQueue.remove(at: index)
                processingManager.processingQueue.insert(job, at: 0)
            }
        }
    }
    
    private func moveJobToBottom(_ job: ProcessingJob) {
        withAnimation(.smooth) {
            if let index = processingManager.processingQueue.firstIndex(where: { $0.id == job.id }) {
                let job = processingManager.processingQueue.remove(at: index)
                processingManager.processingQueue.append(job)
            }
        }
    }
}

// MARK: - Processing Job Row

struct ProcessingJobRow: View {
    let job: ProcessingJob
    let isSelected: Bool
    let onSelect: () -> Void
    let onAction: (JobAction) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: job.status.icon)
                .font(.title2)
                .foregroundStyle(job.status.color)
                .frame(width: 24)
            
            // Job info
            VStack(alignment: .leading, spacing: 4) {
                Text(job.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(job.formattedFileSize)
                    
                    if job.status == .processing {
                        Text("• \(job.estimatedTimeRemaining)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                // Progress bar for active jobs
                if job.status == .processing {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 1.5)
                        .tint(.blue)
                }
                
                // Error message for failed jobs
                if job.status == .failed, let error = job.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Action menu
            Menu {
                if job.status == .failed {
                    Button {
                        onAction(.retry)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
                
                if job.status == .queued {
                    Button {
                        onAction(.moveToTop)
                    } label: {
                        Label("Move to Top", systemImage: "arrow.up.to.line")
                    }
                    
                    Button {
                        onAction(.moveToBottom)
                    } label: {
                        Label("Move to Bottom", systemImage: "arrow.down.to.line")
                    }
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onAction(.remove)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .blue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .blue : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

enum JobAction {
    case retry, remove, moveToTop, moveToBottom
}

// MARK: - Supporting Views

struct ProcessingStatsCard: View {
    let stats: ProcessingStats
    
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 16) {
                StatPill(
                    value: "\(stats.successCount)",
                    label: "Success",
                    color: .green
                )
                
                StatPill(
                    value: "\(stats.failureCount)",
                    label: "Failed",
                    color: .red
                )
                
                if stats.duration > 0 {
                    StatPill(
                        value: formatDuration(stats.duration),
                        label: "Time",
                        color: .blue
                    )
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No files in queue")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Add PDF files to start processing")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
}

struct QueueOverviewView: View {
    @ObservedObject var processingManager: FileProcessingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 8) {
                Text("Select a file to view details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose a file from the queue to see processing information and options")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if processingManager.processingStats.totalFiles > 0 {
                ProcessingStatsDetailCard(stats: processingManager.processingStats)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct ProcessingStatsDetailCard: View {
    let stats: ProcessingStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("Processing Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Total Files:")
                        .foregroundStyle(.secondary)
                    Text("\(stats.totalFiles)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                GridRow {
                    Text("Success Rate:")
                        .foregroundStyle(.secondary)
                    Text("\(Int(stats.successRate * 100))%")
                        .fontWeight(.medium)
                        .foregroundStyle(stats.successRate > 0.8 ? .green : .orange)
                        .monospacedDigit()
                }
                
                if stats.duration > 0 {
                    GridRow {
                        Text("Total Time:")
                            .foregroundStyle(.secondary)
                        Text(formatDuration(stats.duration))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    
                    if stats.averageTimePerFile > 0 {
                        GridRow {
                            Text("Average per File:")
                                .foregroundStyle(.secondary)
                            Text(formatDuration(stats.averageTimePerFile))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

struct JobDetailView: View {
    let job: ProcessingJob
    @ObservedObject var processingManager: FileProcessingManager
    @Binding var showingPreview: Bool
    @Binding var previewURL: URL?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: job.status.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(job.status.color.gradient)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.fileName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        
                        Text(job.status.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(job.status.color)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
                
                // Progress for active job
                if job.status == .processing {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Processing...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(Int(job.progress * 100))%")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 3)
                            .tint(.blue)
                        
                        Text("Estimated time remaining: \(job.estimatedTimeRemaining)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            
            // File details
            JobFileDetailsCard(job: job)
            
            // Actions
            JobActionsCard(
                job: job,
                processingManager: processingManager,
                showingPreview: $showingPreview,
                previewURL: $previewURL
            )
            
            Spacer()
        }
        .padding(24)
    }
}

struct JobFileDetailsCard: View {
    let job: ProcessingJob
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("File Details")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("File Name:")
                        .foregroundStyle(.secondary)
                    Text(job.fileName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                
                GridRow {
                    Text("File Size:")
                        .foregroundStyle(.secondary)
                    Text(job.formattedFileSize)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                GridRow {
                    Text("Estimated Duration:")
                        .foregroundStyle(.secondary)
                    Text(formatDuration(job.estimatedDuration))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                
                if let completedFile = job.completedFile {
                    GridRow {
                        Text("Tables Found:")
                            .foregroundStyle(.secondary)
                        Text("\(completedFile.tablesFound)")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    
                    GridRow {
                        Text("Output Path:")
                            .foregroundStyle(.secondary)
                        Text(completedFile.outputURL.lastPathComponent)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else {
            let minutes = Int(duration / 60)
            return "\(minutes)m"
        }
    }
}

struct JobActionsCard: View {
    let job: ProcessingJob
    @ObservedObject var processingManager: FileProcessingManager
    @Binding var showingPreview: Bool
    @Binding var previewURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "command")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("Actions")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    // Preview original file
                    Button {
                        previewURL = job.fileURL
                        showingPreview = true
                    } label: {
                        Label("Preview PDF", systemImage: "eye.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    // Retry if failed
                    if job.status == .failed {
                        Button {
                            Task {
                                await processingManager.retryFailedJob(job)
                            }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    // Open result if completed
                    if let completedFile = job.completedFile {
                        #if os(macOS)
                        Button {
                            NSWorkspace.shared.open(completedFile.outputURL)
                        } label: {
                            Label("Open Result", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                        #endif
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AddFilesButton: View {
    @ObservedObject var processingManager: FileProcessingManager
    @State private var showingFilePicker = false
    
    var body: some View {
        Button {
            showingFilePicker = true
        } label: {
            Label("Add Files", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await processingManager.addFiles(urls)
                }
            case .failure(let error):
                print("File selection failed: \(error)")
            }
        }
    }
}

#Preview {
    ProcessingQueueView(processingManager: FileProcessingManager())
        .frame(width: 1000, height: 700)
}

