import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let background = CGPath(roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940), cornerWidth: 218, cornerHeight: 218, transform: nil)
        context.saveGState()
        context.addPath(background); context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [color(0.16, 0.22, 0.36), color(0.06, 0.09, 0.17)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: .zero, options: [])
        context.restoreGState()
        let rects: [(CGRect, CGColor)] = [
            (CGRect(x: 172, y: 498, width: 310, height: 334), color(0.94, 0.40, 0.43)),
            (CGRect(x: 530, y: 498, width: 310, height: 334), color(0.64, 0.46, 0.98)),
            (CGRect(x: 172, y: 180, width: 310, height: 270), color(0.28, 0.67, 0.99)),
            (CGRect(x: 530, y: 180, width: 310, height: 270), color(0.30, 0.80, 0.67))
        ]
        for (index, item) in rects.enumerated() {
            let path = CGPath(roundedRect: item.0, cornerWidth: 59, cornerHeight: 59, transform: nil)
            context.setFillColor(item.1.copy(alpha: index == 1 ? 1 : 0.28)!)
            context.addPath(path); context.fillPath()
            context.setStrokeColor(item.1); context.setLineWidth(index == 1 ? 8 : 3)
            context.addPath(path); context.strokePath()
            if index == 1 {
                context.setStrokeColor(color(1, 1, 1, 0.94)); context.setLineWidth(27)
                context.setLineCap(.round); context.setLineJoin(.round)
                context.move(to: CGPoint(x: 622, y: 593)); context.addLine(to: CGPoint(x: 746, y: 717))
                context.move(to: CGPoint(x: 635, y: 717)); context.addLine(to: CGPoint(x: 746, y: 717)); context.addLine(to: CGPoint(x: 746, y: 606))
                context.strokePath()
            } else {
                context.setFillColor(item.1)
                context.fillEllipse(in: CGRect(x: item.0.minX + 46, y: item.0.maxY - 87, width: 33, height: 33))
                let line = CGPath(roundedRect: CGRect(x: item.0.minX + 46, y: item.0.minY + 49, width: 150, height: 17), cornerWidth: 8, cornerHeight: 8, transform: nil)
                context.addPath(line); context.fillPath()
            }
        }
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
    }
}
