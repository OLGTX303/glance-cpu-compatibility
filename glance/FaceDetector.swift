//
//  FaceDetector.swift
//  glance
//
//  Converts Vision's normalized (0...1), bottom-left-origin face boxes into pixel-space, top-left-origin `CGRect`s.
//

import Vision
import CoreGraphics
import Foundation
import CoreImage

struct DetectedFace {
    /// Pixel-space bounding box, top-left origin — ready to crop with.
    let boundingBox: CGRect
    /// Vision's original normalized box — kept as-is since it's the exact format `layerRectConverted(fromMetadataOutputRect:)` expects.
    let normalizedBoundingBox: CGRect
    /// 0...1 confidence from Vision that this is a face, roughly indicating
    /// image quality/pose suitability for recognition. `nil` if the quality
    /// request didn't produce a result for this face.
    let quality: Float?
    /// Head rotation in radians, when Vision could estimate it. Yaw drives the guided-pose onboarding capture;
    /// roll and pitch are exposed but unused today.
    let yaw: Float?
    let roll: Float?
    let pitch: Float?
    /// Facial landmarks (eyes, nose, mouth, etc.), when available. Feeds
    /// `FaceAligner` for canonical 112x112 alignment ahead of ArcFace.
    nonisolated let landmarks: VNFaceLandmarks2D?
    /// Needed by `landmarks.pointsInImage(_:)` to convert normalized landmark points into `boundingBox`'s pixel space.
    let imageSize: CGSize
}

/// Pure, synchronous, CPU-bound work — `nonisolated` so it can run on a
/// background task despite the project's default main-actor isolation.
nonisolated enum FaceDetector {
    // Keep the shared Vision runtime out of overlapping detector invocations.
    private static let detectorLock = NSLock()
    private static let imageContext = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    /// Runs face-rectangle, capture-quality, and landmarks detection on a single frame.
    static func detectFaces(in image: CGImage) throws -> [DetectedFace] {
        detectorLock.lock()
        defer { detectorLock.unlock() }
        let handler = VNImageRequestHandler(cgImage: image, options: [.ciContext: imageContext])

        let rectanglesRequest = VNDetectFaceRectanglesRequest()
        rectanglesRequest.usesCPUOnly = true // CPU compatibility with the custom NVIDIA stack.
        try handler.perform([rectanglesRequest])
        var faceObservations = rectanglesRequest.results ?? []
        if faceObservations.isEmpty {
            // Try the earlier detector before rejecting a frame. Landmarks,
            // measured pose, quality and recognition checks still run below.
            let fallback = VNDetectFaceRectanglesRequest()
            fallback.revision = VNDetectFaceRectanglesRequestRevision2
            fallback.usesCPUOnly = true
            try VNImageRequestHandler(cgImage: image, options: [.ciContext: imageContext]).perform([fallback])
            faceObservations = fallback.results ?? []
        }
        guard !faceObservations.isEmpty else { return [] }

        // Chained to the rectangles results (via `inputFaceObservations`) rather than run independently, so results
        // correspond 1:1 in order — avoids the fragility of matching back via boundingBox float equality.
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.usesCPUOnly = true // CPU compatibility with the custom NVIDIA stack.
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.usesCPUOnly = true // CPU compatibility with the custom NVIDIA stack.
        qualityRequest.inputFaceObservations = faceObservations
        landmarksRequest.inputFaceObservations = faceObservations
        // Separate handlers prevent Vision from combining quality and landmark
        // requests into the ANFD compound network seen in the crash reports.
        try VNImageRequestHandler(cgImage: image, options: [.ciContext: imageContext]).perform([qualityRequest])
        try VNImageRequestHandler(cgImage: image, options: [.ciContext: imageContext]).perform([landmarksRequest])

        let qualityResults = qualityRequest.results ?? []
        let landmarkResults = landmarksRequest.results ?? []
        let imageSize = CGSize(width: image.width, height: image.height)

        return faceObservations.enumerated().map { index, observation in
            let pixelRect = convertToImageSpace(observation.boundingBox, imageSize: imageSize)
            let refined = landmarkResults.indices.contains(index) ? landmarkResults[index] : observation
            return DetectedFace(
                boundingBox: pixelRect,
                normalizedBoundingBox: observation.boundingBox,
                quality: qualityResults.indices.contains(index) ? qualityResults[index].faceCaptureQuality : nil,
                yaw: (refined.yaw ?? observation.yaw)?.floatValue,
                roll: (refined.roll ?? observation.roll)?.floatValue,
                pitch: (refined.pitch ?? observation.pitch)?.floatValue,
                landmarks: landmarkResults.indices.contains(index) ? landmarkResults[index].landmarks : nil,
                imageSize: imageSize
            )
        }
    }

    /// Vision's normalized rect has origin at bottom-left; `CGImage.cropping`
    /// expects pixel coordinates with origin at top-left. This flips the Y axis.
    static func convertToImageSpace(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalizedRect.origin.x * imageSize.width
        let width = normalizedRect.width * imageSize.width
        let height = normalizedRect.height * imageSize.height
        let y = (1 - normalizedRect.origin.y) * imageSize.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Crops `face` out of `image`, padding slightly around the detected box
    /// so the embedder sees a bit of context beyond just eyes/nose/mouth.
    static func crop(_ face: DetectedFace, from image: CGImage, paddingFraction: CGFloat = 0.2) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let padX = face.boundingBox.width * paddingFraction
        let padY = face.boundingBox.height * paddingFraction
        let padded = face.boundingBox.insetBy(dx: -padX, dy: -padY).intersection(imageBounds)
        guard !padded.isEmpty else { return nil }
        return image.cropping(to: padded)
    }
}
