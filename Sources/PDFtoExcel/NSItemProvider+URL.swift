//
//  NSItemProvider+URL.swift
//  PDFtoExcel
//
//  Async URL loading for drag-and-drop handlers.
//

import Foundation

extension NSItemProvider {
    /// Async wrapper around `loadObject(ofClass:completionHandler:)`.
    ///
    /// Drop handlers run on the main thread, so waiting on a `DispatchSemaphore`
    /// for the completion handler blocks the UI for the length of every load and
    /// deadlocks outright when that handler is itself scheduled on the main queue.
    @MainActor
    func loadURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
