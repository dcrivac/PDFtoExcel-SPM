//
//  PageFixtures.swift
//  PDFtoExcelTests
//
//  Synthetic OCR output, so the detection heuristics can be driven from a
//  page whose layout is known exactly.
//

import CoreGraphics
import Foundation
@testable import PDFtoExcel

/// Text positioned the way Vision reports it: normalized coordinates with the
/// origin at the bottom left, so the top line of a page has the largest y.
enum Page {
    static let lineHeight: CGFloat = 0.04
    static let cellHeight: CGFloat = 0.02
    
    /// One run of text, placed by its left edge.
    static func run(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 0.1,
        confidence: Float = 1.0
    ) -> TextRun {
        TextRun(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: cellHeight),
            confidence: confidence
        )
    }
    
    /// A grid of cells, written top to bottom, left to right.
    ///
    /// An empty string contributes no run at all, which is what OCR reports for
    /// a blank cell — the absence is the thing the column logic has to survive.
    ///
    /// - Parameter slope: Page tilt, as the rise in y across the full page
    ///   width. Applied about each cell's centre, matching how `TextSkew`
    ///   measures it.
    static func grid(
        _ rows: [[String]],
        columnX: [CGFloat],
        topY: CGFloat = 0.9,
        lineHeight: CGFloat = lineHeight,
        cellWidth: CGFloat = 0.1,
        slope: CGFloat = 0
    ) -> [TextRun] {
        var runs: [TextRun] = []
        
        for (rowIndex, row) in rows.enumerated() {
            let y = topY - CGFloat(rowIndex) * lineHeight
            
            for (columnIndex, text) in row.enumerated() where !text.isEmpty {
                let x = columnX[columnIndex]
                runs.append(run(
                    text,
                    x: x,
                    y: y + (x + cellWidth / 2) * slope,
                    width: cellWidth
                ))
            }
        }
        
        return runs
    }
    
    /// A grid whose cells are centred on their columns rather than left
    /// aligned, sized to the text they hold.
    static func centredGrid(
        _ rows: [[String]],
        columnX: [CGFloat],
        topY: CGFloat = 0.9,
        lineHeight: CGFloat = lineHeight,
        widthPerCharacter: CGFloat = 0.02
    ) -> [TextRun] {
        anchoredGrid(
            rows,
            columnX: columnX,
            topY: topY,
            lineHeight: lineHeight,
            widthPerCharacter: widthPerCharacter,
            leftEdge: { centre, width in centre - width / 2 }
        )
    }
    
    /// A grid whose cells share a right edge, as a column of figures does.
    static func rightAlignedGrid(
        _ rows: [[String]],
        columnX: [CGFloat],
        topY: CGFloat = 0.9,
        lineHeight: CGFloat = lineHeight,
        widthPerCharacter: CGFloat = 0.02
    ) -> [TextRun] {
        anchoredGrid(
            rows,
            columnX: columnX,
            topY: topY,
            lineHeight: lineHeight,
            widthPerCharacter: widthPerCharacter,
            leftEdge: { edge, width in edge - width }
        )
    }
    
    private static func anchoredGrid(
        _ rows: [[String]],
        columnX: [CGFloat],
        topY: CGFloat,
        lineHeight: CGFloat,
        widthPerCharacter: CGFloat,
        leftEdge: (CGFloat, CGFloat) -> CGFloat
    ) -> [TextRun] {
        var runs: [TextRun] = []
        
        for (rowIndex, row) in rows.enumerated() {
            let y = topY - CGFloat(rowIndex) * lineHeight
            
            for (columnIndex, text) in row.enumerated() where !text.isEmpty {
                let width = CGFloat(text.count) * widthPerCharacter
                runs.append(run(
                    text,
                    x: leftEdge(columnX[columnIndex], width),
                    y: y,
                    width: width
                ))
            }
        }
        
        return runs
    }
}
