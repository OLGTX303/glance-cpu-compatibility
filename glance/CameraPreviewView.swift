// CPU preview: share the owned camera frame, avoiding AVCaptureVideoPreviewLayer.
import SwiftUI
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let image: CGImage?
    var faces: [DetectedFace] = []

    func makeNSView(context: Context) -> PreviewHostView { PreviewHostView(frame: .zero) }
    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        nsView.image = image
        nsView.faces = faces
        nsView.needsDisplay = true
    }
}

final class PreviewHostView: NSView {
    var image: CGImage?
    var faces: [DetectedFace] = []

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext,
              bounds.width > 0, bounds.height > 0 else { return }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = max(bounds.width / width, bounds.height / height)
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: -scale, y: scale)
        context.translateBy(x: -width / 2, y: -height / 2)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(NSColor.systemGreen.cgColor)
        context.setLineWidth(2 / scale)
        for face in faces {
            let box = face.boundingBox
            context.stroke(CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height))
        }
    }
}
