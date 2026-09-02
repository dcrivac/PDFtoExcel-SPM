//
//  TextRecognition.swift
//  PDFtoExcel
//
//  Text recognition that levels a tilted page before reading it.
//

import CoreGraphics
import Foundation
import OSLog
import Vision

enum TextRecognition {
    private static let logger = Logger(subsystem: "com.pdftoexcel.app", category: "TextRecognition")
    
    /// Recognize the text in a page image, straightening it first if it is
    /// noticeably tilted.
    ///
    /// Vision reads tilted glyphs less reliably than upright ones and will drop
    /// words outright on a badly skewed scan, but the tilt can only be measured
    /// once there is text to measure it from. So the page is read as it stands,
    /// and only if that first pass shows a meaningful tilt is the image levelled
    /// and read again.
    ///
    /// The second reading is kept only when it recovers at least as much text as
    /// the first, so a rotation that happens to hurt cannot make the result
    /// worse than doing nothing.
    ///
    /// - Parameters:
    ///   - image: The rendered page.
    ///   - configure: Applies the caller's recognition settings to each request.
    static func observations(
        in image: CGImage,
        configure: (VNRecognizeTextRequest) -> Void
    ) throws -> [VNRecognizedTextObservation] {
        let first = try read(image, configure: configure)
        
        let slope = TextSkew.estimateSlope(of: TextRun.runs(from: first))
        let size = CGSize(width: image.width, height: image.height)
        let angle = TextSkew.angle(forSlope: slope, imageSize: size)
        guard abs(angle) >= TextSkew.rereadThreshold,
              let levelled = TextSkew.levelled(image, byRotating: angle) else {
            return first
        }
        
        let second = try read(levelled, configure: configure)
        guard second.count >= first.count else {
            logger.debug("Levelled pass recovered less text; keeping the original reading")
            return first
        }
        
        logger.debug("Levelled page by \(angle * 180 / .pi, format: .fixed(precision: 2))°, \(first.count) -> \(second.count) observations")
        return second
    }
    
    private static func read(
        _ image: CGImage,
        configure: (VNRecognizeTextRequest) -> Void
    ) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        configure(request)
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results ?? []
    }
}
