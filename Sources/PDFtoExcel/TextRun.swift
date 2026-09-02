//
//  TextRun.swift
//  PDFtoExcel
//
//  The unit of recognized text the detection heuristics work on.
//

import CoreGraphics
import Foundation
import Vision

/// A run of recognized text and the box it occupies on the page.
///
/// Vision's `VNRecognizedTextObservation` cannot be constructed outside the
/// framework, which puts every heuristic that reads one out of reach of a test.
/// The detection pipeline works on this instead and converts at the boundary,
/// so row grouping, column alignment and tilt estimation can all be driven from
/// positions written by hand.
struct TextRun: Equatable, Sendable {
    var text: String
    /// Normalized page coordinates, as Vision reports them: origin at the
    /// bottom left, both axes running 0 to 1.
    var boundingBox: CGRect
    var confidence: Float
    
    init(text: String, boundingBox: CGRect, confidence: Float = 1.0) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
    
    var minX: CGFloat { boundingBox.minX }
    var maxX: CGFloat { boundingBox.maxX }
    var midX: CGFloat { boundingBox.midX }
    var midY: CGFloat { boundingBox.midY }
}

extension TextRun {
    /// The text Vision recognized, in the order it was reported.
    ///
    /// An observation carrying no candidate is dropped: it has no text to place
    /// in a cell, and counting it would still let it pull on the tilt estimate.
    static func runs(from observations: [VNRecognizedTextObservation]) -> [TextRun] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextRun(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: observation.confidence
            )
        }
    }
}
