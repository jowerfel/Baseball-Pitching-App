import SwiftUI
import CoreGraphics
import Foundation

enum SkeletonRenderer {
    private static let strokeColor = CGColor(red: 0, green: 229 / 255, blue: 1, alpha: 1)
    private static let jointRadius: CGFloat = 5
    private static let strokeWidth: CGFloat = 2
    private static let segmentPairs: [(String, String)] = [
        ("leftShoulder", "leftElbow"),
        ("leftElbow", "leftWrist"),
        ("rightShoulder", "rightElbow"),
        ("rightElbow", "rightWrist"),
        ("leftHip", "leftKnee"),
        ("leftKnee", "leftAnkle"),
        ("rightHip", "rightKnee"),
        ("rightKnee", "rightAnkle"),
        ("leftShoulder", "rightShoulder"),
        ("leftHip", "rightHip"),
        ("leftShoulder", "leftHip"),
        ("rightShoulder", "rightHip"),
    ]

    static func drawSkeleton(for landmarks: [BodyLandmark], in context: CGContext, canvasSize: CGSize) {
        guard !landmarks.isEmpty else {
            return
        }

        let pointLookup = Dictionary(uniqueKeysWithValues: landmarks.map { landmark in
            (landmark.jointName, CGPoint(x: landmark.x * canvasSize.width, y: landmark.y * canvasSize.height))
        })

        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.fill(CGRect(origin: .zero, size: canvasSize))

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for (startName, endName) in segmentPairs {
            guard let start = pointLookup[startName], let end = pointLookup[endName] else {
                continue
            }

            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        context.setFillColor(strokeColor)
        for point in pointLookup.values {
            let rect = CGRect(
                x: point.x - jointRadius,
                y: point.y - jointRadius,
                width: jointRadius * 2,
                height: jointRadius * 2
            )
            context.fillEllipse(in: rect)
        }

        context.restoreGState()
    }

    static func drawSkeleton(for landmarks: [BodyLandmark], in context: GraphicsContext, canvasSize: CGSize) {
        guard !landmarks.isEmpty else {
            return
        }

        context.withCGContext { cgContext in
            drawSkeleton(for: landmarks, in: cgContext, canvasSize: canvasSize)
        }
    }
}
