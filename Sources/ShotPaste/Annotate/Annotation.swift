import AppKit
import CoreImage
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, pen, highlight, text, counter, pixelate

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .pixelate: return "mosaic"
        }
    }

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .text: return "Text"
        case .counter: return "Step counter"
        case .pixelate: return "Pixelate (hide sensitive info)"
        }
    }
}

/// A single shape. Points are in image coordinates (points, top-left origin).
struct Annotation: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var color: Color
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String = ""
    var number: Int = 0

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Draws annotations into a SwiftUI GraphicsContext. Used both for the live
/// editor canvas and for the final export so they always match.
enum AnnotationRenderer {
    static func draw(_ annotations: [Annotation], in ctx: GraphicsContext, imageSize: CGSize, pixelated: Image) {
        for a in annotations {
            draw(a, in: ctx, imageSize: imageSize, pixelated: pixelated)
        }
    }

    static func draw(_ a: Annotation, in ctx: GraphicsContext, imageSize: CGSize, pixelated: Image) {
        let shading = GraphicsContext.Shading.color(a.color)
        let stroke = StrokeStyle(lineWidth: a.lineWidth, lineCap: .round, lineJoin: .round)

        switch a.tool {
        case .pen:
            var path = Path()
            path.addLines(a.points)
            ctx.stroke(path, with: shading, style: stroke)

        case .rectangle:
            ctx.stroke(Path(roundedRect: a.rect, cornerRadius: 3), with: shading, style: stroke)

        case .ellipse:
            ctx.stroke(Path(ellipseIn: a.rect), with: shading, style: stroke)

        case .highlight:
            ctx.fill(Path(a.rect), with: .color(a.color.opacity(0.35)))

        case .arrow:
            guard let s = a.points.first, let e = a.points.last else { return }
            let angle = atan2(e.y - s.y, e.x - s.x)
            let head = max(14, a.lineWidth * 4)
            // Stop the shaft inside the head so the tip stays sharp.
            let shaftEnd = CGPoint(x: e.x - cos(angle) * head * 0.6, y: e.y - sin(angle) * head * 0.6)
            var shaft = Path()
            shaft.move(to: s)
            shaft.addLine(to: shaftEnd)
            ctx.stroke(shaft, with: shading, style: stroke)

            var tip = Path()
            tip.move(to: e)
            tip.addLine(to: CGPoint(x: e.x - head * cos(angle - .pi / 7), y: e.y - head * sin(angle - .pi / 7)))
            tip.addLine(to: CGPoint(x: e.x - head * cos(angle + .pi / 7), y: e.y - head * sin(angle + .pi / 7)))
            tip.closeSubpath()
            ctx.fill(tip, with: shading)

        case .text:
            guard let p = a.points.first else { return }
            let text = Text(a.text)
                .font(.system(size: 10 + a.lineWidth * 3, weight: .semibold))
                .foregroundColor(a.color)
            ctx.draw(text, at: p, anchor: .topLeading)

        case .counter:
            guard let p = a.points.first else { return }
            let r = 10 + a.lineWidth * 1.5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: shading)
            let label = Text("\(a.number)")
                .font(.system(size: r, weight: .bold))
                .foregroundColor(.white)
            ctx.draw(label, at: p, anchor: .center)

        case .pixelate:
            var clipped = ctx
            clipped.clip(to: Path(a.rect))
            clipped.draw(pixelated, in: CGRect(origin: .zero, size: imageSize))
        }
    }

    /// A fully pixelated copy of the image; the pixelate tool reveals it through a clip.
    static func pixelate(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(12, input.extent.width / 70), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}
