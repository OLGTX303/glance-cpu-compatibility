// Camera pixel ownership, scaling and crops without Core Image/OpenCL rendering.
import CoreGraphics
import CoreVideo
import Foundation

nonisolated enum CPUFrameRenderer {
    static func images(from buffer: CVPixelBuffer, maxLongEdge: CGFloat = 640) -> (native: CGImage, working: CGImage)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let (length, overflow) = stride.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflow, length > 0,
              length <= CVPixelBufferGetDataSize(buffer),
              let base = CVPixelBufferGetBaseAddress(buffer),
              let data = CFDataCreate(kCFAllocatorDefault, base.assumingMemoryBound(to: UInt8.self), length),
              let provider = CGDataProvider(data: data),
              let native = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let working = scaled(native, maxLongEdge: maxLongEdge) else { return nil }
        // CFData owns a copy: the camera is free to reuse the original buffer.
        return (native, working)
    }

    static func scaled(_ image: CGImage, maxLongEdge: CGFloat) -> CGImage? {
        guard maxLongEdge.isFinite, maxLongEdge >= 1 else { return nil }
        let longEdge = CGFloat(max(image.width, image.height))
        if longEdge <= maxLongEdge { return image }
        let scale = maxLongEdge / longEdge
        let width = max(1, Int((CGFloat(image.width) * scale).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded(.down)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func crop(_ source: CGImage, workingSize: CGSize, imageRect: CGRect, maxEdge: CGFloat = 448) -> CGImage? {
        guard workingSize.width.isFinite, workingSize.height.isFinite,
              workingSize.width > 0, workingSize.height > 0,
              [imageRect.origin.x, imageRect.origin.y, imageRect.width, imageRect.height].allSatisfy({ $0.isFinite }),
              imageRect.width > 0, imageRect.height > 0 else { return nil }
        let expanded = imageRect.insetBy(dx: -imageRect.width * 0.15, dy: -imageRect.height * 0.15)
        let scaleX = CGFloat(source.width) / workingSize.width
        let scaleY = CGFloat(source.height) / workingSize.height
        // CGImage crops use pixel coordinates from the top-left, like imageRect.
        let rect = CGRect(x: expanded.minX * scaleX, y: expanded.minY * scaleY,
                          width: expanded.width * scaleX, height: expanded.height * scaleY)
            .integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !rect.isNull, !rect.isEmpty, let crop = source.cropping(to: rect) else { return nil }
        return scaled(crop, maxLongEdge: maxEdge)
    }
}
