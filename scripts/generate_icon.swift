// Renders the NotchPilot app icon as a 1024×1024 PNG.
// Usage: swift scripts/generate_icon.swift <output.png>
// Then: scripts/make_icon.sh turns it into Support/AppIcon.icns.

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let canvas = 1024

guard let context = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("could not create bitmap context")
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// macOS icon grid: content is a rounded square inset from the canvas.
let squareRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squareRadius: CGFloat = 185

// Background rounded square with a subtle vertical gradient.
let squarePath = CGPath(roundedRect: squareRect, cornerWidth: squareRadius, cornerHeight: squareRadius, transform: nil)
context.saveGState()
context.addPath(squarePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0x2E2E38), color(0x17171C)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: squareRect.midX, y: squareRect.maxY),
    end: CGPoint(x: squareRect.midX, y: squareRect.minY),
    options: []
)

// The notch: a bar hugging the top edge with rounded bottom corners.
let notchWidth: CGFloat = 400
let notchHeight: CGFloat = 130
let notchRadius: CGFloat = 52
let notchRect = CGRect(
    x: squareRect.midX - notchWidth / 2,
    y: squareRect.maxY - notchHeight,
    width: notchWidth,
    height: notchHeight
)
let notchPath = CGMutablePath()
notchPath.move(to: CGPoint(x: notchRect.minX, y: notchRect.maxY))
notchPath.addLine(to: CGPoint(x: notchRect.minX, y: notchRect.minY + notchRadius))
notchPath.addArc(
    center: CGPoint(x: notchRect.minX + notchRadius, y: notchRect.minY + notchRadius),
    radius: notchRadius, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false
)
notchPath.addLine(to: CGPoint(x: notchRect.maxX - notchRadius, y: notchRect.minY))
notchPath.addArc(
    center: CGPoint(x: notchRect.maxX - notchRadius, y: notchRect.minY + notchRadius),
    radius: notchRadius, startAngle: 1.5 * .pi, endAngle: 0, clockwise: false
)
notchPath.addLine(to: CGPoint(x: notchRect.maxX, y: notchRect.maxY))
notchPath.closeSubpath()
context.setFillColor(color(0x000000))
context.addPath(notchPath)
context.fillPath()

// Status dots: green (working), orange (needs attention), dim (idle).
let dotY = squareRect.minY + squareRect.height * 0.42
let dotRadius: CGFloat = 62
let spacing: CGFloat = 210
let dots: [(CGFloat, UInt32, CGFloat)] = [
    (squareRect.midX - spacing, 0x34C759, 1.0),
    (squareRect.midX, 0xFF9F0A, 1.0),
    (squareRect.midX + spacing, 0x8E8E93, 0.55),
]
for (x, hex, alpha) in dots {
    // Soft glow.
    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: 70,
        color: color(hex, alpha: 0.55 * alpha)
    )
    context.setFillColor(color(hex, alpha: alpha))
    context.fillEllipse(in: CGRect(x: x - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    context.restoreGState()
}

// Hairline inner border for definition on light backgrounds.
context.addPath(CGPath(
    roundedRect: squareRect.insetBy(dx: 3, dy: 3),
    cornerWidth: squareRadius - 3,
    cornerHeight: squareRadius - 3,
    transform: nil
))
context.setStrokeColor(color(0xFFFFFF, alpha: 0.07))
context.setLineWidth(6)
context.strokePath()
context.restoreGState()

guard let image = context.makeImage() else {
    fatalError("could not render image")
}
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
