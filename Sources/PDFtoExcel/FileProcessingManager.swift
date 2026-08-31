//
//  FileProcessingManager.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/15/25.
//

import Foundation
import SwiftUI
import Combine
import OSLog
import QuickLook
import UniformTypeIdentifiers
import PDFKit

// MARK: - File Processing Manager

@MainActor
class FileProcessingManager: ObservableObject {
    @Published var processingQueue: [ProcessingJob] = []
    @Published var completedJobs: [ProcessedFile] = []
    @Published var isProcessing = false
    @Published var overallProgress: Double = 0.0
    @Published var currentJob: ProcessingJob?
    @Published var processingStats = ProcessingStats()
    
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "FileProcessing")
    private let converter = PDFToExcelConverter()
    private let fileValidator = FileValidator()
    
    // MARK: - Public Methods
    
    func addFiles(_ urls: [URL]) async {
        let validationResults = await fileValidator.validateFiles(urls)
        
        for result in validationResults {
            switch result.status {
            case .valid:
                let job = ProcessingJob(
                    id: UUID(),
                    fileURL: result.url,
                    fileName: result.url.lastPathComponent,
                    fileSize: result.fileSize ?? 0,
                    status: .queued,
                    progress: 0.0,
                    estimatedDuration: estimateProcessingTime(for: result.fileSize ?? 0)
                )
                processingQueue.append(job)
                
            case .invalid(let error):
                logger.error("Invalid file: \(result.url.lastPathComponent) - \(error)")
                await showValidationError(for: result.url, error: error)
            }
        }
        
        if !processingQueue.isEmpty && !isProcessing {
            await startProcessing()
        }
    }
    
    func removeJob(_ job: ProcessingJob) {
        processingQueue.removeAll { $0.id == job.id }
        updateProgress()
    }
    
    func clearQueue() {
        processingQueue.removeAll()
        updateProgress()
    }
    
    func retryFailedJob(_ job: ProcessingJob) async {
        if let index = processingQueue.firstIndex(where: { $0.id == job.id }) {
            processingQueue[index].status = .queued
            processingQueue[index].progress = 0.0
            processingQueue[index].errorMessage = nil
            
            if !isProcessing {
                await startProcessing()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startProcessing() async {
        guard !isProcessing, !processingQueue.isEmpty else { return }
        
        isProcessing = true
        self.processingStats.startTime = Date()
        self.processingStats.totalFiles = processingQueue.count
        
        logger.info("Starting batch processing of \(self.processingQueue.count) files")
        
        while let nextJob = processingQueue.first(where: { $0.status == .queued }) {
            currentJob = nextJob
            await processJob(nextJob)
        }
        
        // Processing complete
        isProcessing = false
        currentJob = nil
        self.processingStats.endTime = Date()
        
        logger.info("Batch processing completed. Processed: \(self.processingStats.successCount), Failed: \(self.processingStats.failureCount)")
    }
    
    private func processJob(_ job: ProcessingJob) async {
        updateJobStatus(job, to: .processing)
        
        // Ensure security-scoped access during processing
        let didStartAccess = job.fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                job.fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Update progress periodically during processing
            let progressTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    await MainActor.run {
                        if let index = self.processingQueue.firstIndex(where: { $0.id == job.id }) {
                            self.processingQueue[index].progress = min(self.processingQueue[index].progress + 0.02, 0.9)
                            self.updateProgress()
                        }
                    }
                }
            }
            
            // Process the file using the converter's public method
            let processedFile = try await converter.convertSingleFile(job.fileURL)
            
            progressTask.cancel()
            
            // Complete the job
            await MainActor.run {
                self.updateJobStatus(job, to: .completed)
                if let index = self.processingQueue.firstIndex(where: { $0.id == job.id }) {
                    self.processingQueue[index].progress = 1.0
                    self.processingQueue[index].completedFile = processedFile
                }
                
                self.completedJobs.append(processedFile)
                self.processingStats.successCount += 1
                self.updateProgress()
            }
            
            logger.info("Successfully processed: \(job.fileName)")
            
        } catch {
            updateJobStatus(job, to: .failed, error: error.localizedDescription)
            self.processingStats.failureCount += 1
            logger.error("Failed to process \(job.fileName): \(error.localizedDescription)")
        }
    }
    
    private func updateJobStatus(_ job: ProcessingJob, to status: ProcessingStatus, error: String? = nil) {
        if let index = processingQueue.firstIndex(where: { $0.id == job.id }) {
            processingQueue[index].status = status
            processingQueue[index].errorMessage = error
        }
    }
    
    private func updateProgress() {
        let totalJobs = max(processingQueue.count, 1)
        let completedJobs = processingQueue.filter { $0.status == .completed }.count
        let inProgressJobs = processingQueue.filter { $0.status == .processing }
        
        var progress = Double(completedJobs) / Double(totalJobs)
        
        // Add partial progress from current job
        if let inProgressJob = inProgressJobs.first {
            progress += (inProgressJob.progress / Double(totalJobs))
        }
        
        overallProgress = min(progress, 1.0)
    }
    
    private func estimateProcessingTime(for fileSize: Int64) -> TimeInterval {
        // Rough estimate: 1MB = 2 seconds processing time
        let megabytes = Double(fileSize) / (1024 * 1024)
        return max(megabytes * 2.0, 1.0)
    }
    
    private func showValidationError(for url: URL, error: ValidationError) async {
        // This would typically show an alert or notification
        // For now, we'll just log it
        logger.warning("Validation error for \(url.lastPathComponent): \(error.localizedDescription)")
    }
}

// MARK: - Data Models

struct ProcessingJob: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    var status: ProcessingStatus
    var progress: Double
    var errorMessage: String?
    var estimatedDuration: TimeInterval
    var completedFile: ProcessedFile?
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var estimatedTimeRemaining: String {
        let remaining = estimatedDuration * (1.0 - progress)
        if remaining < 60 {
            return "\(Int(remaining))s"
        } else {
            return "\(Int(remaining / 60))m \(Int(remaining.truncatingRemainder(dividingBy: 60)))s"
        }
    }
}

enum ProcessingStatus: String, CaseIterable {
    case queued = "Queued"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    
    var icon: String {
        switch self {
        case .queued: return "clock.fill"
        case .processing: return "gear.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .queued: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct ProcessingStats {
    var startTime: Date?
    var endTime: Date?
    var totalFiles: Int = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    
    var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var averageTimePerFile: TimeInterval {
        guard successCount > 0 else { return 0 }
        return duration / Double(successCount)
    }
    
    var successRate: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(successCount) / Double(totalFiles)
    }
}

// MARK: - File Validator

final class FileValidator: Sendable {
    private let logger = Logger(subsystem: "com.pdftoexcel.app", category: "FileValidator")
    
    func validateFiles(_ urls: [URL]) async -> [ValidationResult] {
        return await withTaskGroup(of: ValidationResult.self, returning: [ValidationResult].self) { group in
            for url in urls {
                group.addTask {
                    await self.validateFile(url)
                }
            }
            
            var results: [ValidationResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        }
    }
    
    private func validateFile(_ url: URL) async -> ValidationResult {
        do {
            // Check file accessibility
            guard url.startAccessingSecurityScopedResource() else {
                return ValidationResult(url: url, status: .invalid(.fileNotAccessible))
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Check file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ValidationResult(url: url, status: .invalid(.fileNotFound))
            }
            
            // Check file type
            guard url.pathExtension.lowercased() == "pdf" else {
                return ValidationResult(url: url, status: .invalid(.invalidFileType))
            }
            
            // Get file attributes
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            // Check file size (max 100MB)
            guard fileSize > 0 else {
                return ValidationResult(url: url, status: .invalid(.emptyFile))
            }
            
            guard fileSize < 100 * 1024 * 1024 else {
                return ValidationResult(url: url, status: .invalid(.fileTooLarge))
            }
            
            // Try to create PDFDocument to verify it's a valid PDF
            guard let _ = PDFKit.PDFDocument(url: url) else {
                return ValidationResult(url: url, status: .invalid(.corruptedPDF))
            }
            
            return ValidationResult(
                url: url,
                status: .valid,
                fileSize: fileSize
            )
            
        } catch {
            return ValidationResult(
                url: url,
                status: .invalid(.unknownError(error.localizedDescription))
            )
        }
    }
}

struct ValidationResult {
    let url: URL
    let status: ValidationStatus
    let fileSize: Int64?
    
    init(url: URL, status: ValidationStatus, fileSize: Int64? = nil) {
        self.url = url
        self.status = status
        self.fileSize = fileSize
    }
}

enum ValidationStatus {
    case valid
    case invalid(ValidationError)
}

enum ValidationError: LocalizedError {
    case fileNotFound
    case fileNotAccessible
    case invalidFileType
    case emptyFile
    case fileTooLarge
    case corruptedPDF
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .fileNotAccessible:
            return "Cannot access file"
        case .invalidFileType:
            return "File is not a PDF"
        case .emptyFile:
            return "File is empty"
        case .fileTooLarge:
            return "File is too large (max 100MB)"
        case .corruptedPDF:
            return "PDF file is corrupted or invalid"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

