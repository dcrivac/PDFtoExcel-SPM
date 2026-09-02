//
//  TextSkew.swift
//  PDFtoExcel
//
//  Page tilt estimation for OCR output.
//

import CoreGraphics
import CoreImage
import Foundation

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
    /// How much better than level a tilt must score before it is believed.
    ///
    /// Some slope always scores marginally best, even on a square page: with
    /// multiple columns of prose a slanted reading can line up one column's
    /// rows against another's and edge ahead on noise alone. Measured over real
    /// scanner output that spurious margin stayed under 5%, while genuinely
    /// tilted pages gained 100% or more, because levelling collapses each row
    /// from several bands into one. Anything in between is treated as square.
    private static let believableGain = 1.3
    
    /// Tilt above which it is worth re-reading a levelled image.
    ///
    /// Vision copes with a few degrees on its own; measured against simulated
    /// scans it only started dropping words between three and four degrees, so
    /// straighter pages would pay for a second recognition pass and gain
    /// nothing.
    static let rereadThreshold: CGFloat = 2.0 * .pi / 180
    
    /// The page tilt this slope represents.
    ///
    /// Slopes are measured in Vision's normalized space, where both axes run 0
    /// to 1, so the page's aspect ratio has to be restored to get a real angle.
    static func angle(forSlope slope: CGFloat, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0 else { return 0 }
        return atan(slope * imageSize.height / imageSize.width)
    }
    
    /// The image rotated back to level, or nil if it could not be rendered.
    static func levelled(_ image: CGImage, byRotating angle: CGFloat) -> CGImage? {
        let source = CIImage(cgImage: image)
        // Rotating expands the bounds; render the whole rotated extent so no
        // corner of the page is cropped away.
        let rotated = source.transformed(by: CGAffineTransform(rotationAngle: -angle))
        return sharedContext.createCGImage(rotated, from: rotated.extent)
    }
    
    private static let sharedContext = CIContext()
    
    /// Vertical position of a run once the page is levelled.
    static func deskewedY(_ run: TextRun, slope: CGFloat) -> CGFloat {
        run.midY - run.midX * slope
    }
    
    /// Estimated tilt of the page these runs came from.
    ///
    /// Returns zero when there is too little text to judge, which leaves the
    /// caller's positions untouched.
    static func estimateSlope(of runs: [TextRun]) -> CGFloat {
        guard runs.count >= 4 else { return 0 }
        
        let points = runs.map { ($0.midX, $0.midY) }
        
        let levelScore = concentration(of: points, at: 0)
        
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
        
        // Report square unless the winner is a clear improvement on level.
        guard bestScore >= levelScore * believableGain else { return 0 }
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
