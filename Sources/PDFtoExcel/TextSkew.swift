//
//  TextSkew.swift
//  PDFtoExcel
//
//  Page tilt estimation for OCR output.
//

import Foundation
import Vision

/// Recovers the tilt of a scanned page from its recognized text.
///
/// Vision reports an axis-aligned quad for most short words, so a page's tilt
/// cannot be read from any single observation. It shows up instead in how the
/// observations sit relative to one another: on a tilted page the cells of one
/// row climb steadily across the page, which is enough to split one printed line
/// into two logical rows and stagger every value after it.
///
/// Candidate slopes are tried in turn and the one that packs observations into
/// the fewest, densest horizontal bands wins, since a row only collapses into a
/// single band when the page has been levelled.
enum TextSkew {
    /// Largest tilt worth correcting, as a slope in Vision's normalized space.
    /// About 5 degrees on a portrait page, beyond what document scanning
    /// realistically produces.
    private static let maxSlope: CGFloat = 0.12
    private static let slopeStep: CGFloat = 0.002
    /// Roughly a quarter of the spacing between printed lines.
    private static let bandHeight: CGFloat = 0.008
    
    /// Vertical position of an observation once the page is levelled.
    static func deskewedY(_ observation: VNRecognizedTextObservation, slope: CGFloat) -> CGFloat {
        let box = observation.boundingBox
        return box.midY - box.midX * slope
    }
    
    /// Estimated tilt of the page these observations came from.
    ///
    /// Returns zero when there is too little text to judge, which leaves the
    /// caller's positions untouched.
    static func estimateSlope(of observations: [VNRecognizedTextObservation]) -> CGFloat {
        guard observations.count >= 4 else { return 0 }
        
        let points = observations.map { ($0.boundingBox.midX, $0.boundingBox.midY) }
        
        var bestSlope: CGFloat = 0
        var bestScore = -1.0
        
        var slope = -maxSlope
        while slope <= maxSlope {
            let score = concentration(of: points, at: slope)
            // Ties favour the smaller correction, so an untilted page is left
            // alone rather than nudged by whichever candidate was tried first.
            if score > bestScore || (score == bestScore && abs(slope) < abs(bestSlope)) {
                bestScore = score
                bestSlope = slope
            }
            slope += slopeStep
        }
        
        return bestSlope
    }
    
    /// How tightly rows bunch together once this slope is removed.
    private static func concentration(of points: [(CGFloat, CGFloat)], at slope: CGFloat) -> Double {
        // Two band grids, offset by half a band, so that a row straddling a
        // boundary in one grid still lands whole in the other.
        var gridA: [Int: Int] = [:]
        var gridB: [Int: Int] = [:]
        
        for (x, y) in points {
            let corrected = y - x * slope
            gridA[Int((corrected / bandHeight).rounded(.down)), default: 0] += 1
            gridB[Int(((corrected + bandHeight / 2) / bandHeight).rounded(.down)), default: 0] += 1
        }
        
        // Squared counts reward whole rows sharing one band.
        let scoreA = gridA.values.reduce(0.0) { $0 + Double($1 * $1) }
        let scoreB = gridB.values.reduce(0.0) { $0 + Double($1 * $1) }
        return max(scoreA, scoreB)
    }
}
