import AppKit

private func imageRep(size: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
}

private func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

private func withContext(size: Int, scale: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = imageRep(size: size * scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func drawControlCenterGlyph(in context: CGContext) {
    let speaker = CGMutablePath()
    speaker.move(to: CGPoint(x: 1.7, y: 12.0))
    speaker.addLine(to: CGPoint(x: 6.7, y: 12.0))
    speaker.addLine(to: CGPoint(x: 13.0, y: 7.0))
    speaker.addLine(to: CGPoint(x: 13.0, y: 23.0))
    speaker.addLine(to: CGPoint(x: 6.7, y: 18.0))
    speaker.addLine(to: CGPoint(x: 1.7, y: 18.0))
    speaker.closeSubpath()
    context.addPath(speaker)
    context.fillPath()

    context.setLineWidth(2.65)
    context.setLineCap(.round)
    context.addArc(center: CGPoint(x: 12.7, y: 15.0), radius: 5.2, startAngle: -0.72, endAngle: 0.72, clockwise: false)
    context.strokePath()

    let device = CGPath(roundedRect: CGRect(x: 20.7, y: 9.2, width: 5.0, height: 11.3), cornerWidth: 1.8, cornerHeight: 1.8, transform: nil)
    context.addPath(device)
    context.strokePath()
    context.setLineWidth(2.0)
    context.addArc(center: CGPoint(x: 23.2, y: 14.9), radius: 5.0, startAngle: 2.32, endAngle: 3.96, clockwise: false)
    context.strokePath()
    context.addArc(center: CGPoint(x: 23.2, y: 14.9), radius: 5.0, startAngle: -0.82, endAngle: 0.82, clockwise: false)
    context.strokePath()
}

private func controlCenterIcon(selected: Bool, scale: Int, path: String) {
    let rep = withContext(size: 30, scale: scale) { context in
        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        drawControlCenterGlyph(in: context)
        if selected {
            context.setLineWidth(3.4)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 3.3, y: 25.7))
            context.addLine(to: CGPoint(x: 26.3, y: 3.7))
            context.strokePath()
        }
    }
    writePNG(rep, to: path)
}

private func preferenceIcon(scale: Int, path: String) {
    let rep = withContext(size: 29, scale: scale) { context in
        let bounds = CGRect(x: 0, y: 0, width: 29, height: 29)
        let background = CGPath(roundedRect: bounds, cornerWidth: 6.7, cornerHeight: 6.7, transform: nil)
        context.saveGState()
        context.addPath(background)
        context.clip()
        let colors = [
            NSColor(red: 0.21, green: 0.71, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.40, green: 0.34, blue: 0.96, alpha: 1).cgColor
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 2, y: 27), end: CGPoint(x: 27, y: 2), options: [])
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.setLineWidth(2.25)
        context.setLineCap(.round)
        context.addArc(center: CGPoint(x: 14.5, y: 18.3), radius: 5.1, startAngle: 0, endAngle: .pi, clockwise: false)
        context.strokePath()
        let lockBody = CGPath(roundedRect: CGRect(x: 6.2, y: 5.0, width: 16.6, height: 13.8), cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
        context.addPath(lockBody)
        context.strokePath()

        let speaker = CGMutablePath()
        speaker.move(to: CGPoint(x: 9.0, y: 10.3))
        speaker.addLine(to: CGPoint(x: 11.3, y: 10.3))
        speaker.addLine(to: CGPoint(x: 14.5, y: 7.8))
        speaker.addLine(to: CGPoint(x: 14.5, y: 16.0))
        speaker.addLine(to: CGPoint(x: 11.3, y: 13.5))
        speaker.addLine(to: CGPoint(x: 9.0, y: 13.5))
        speaker.closeSubpath()
        context.addPath(speaker)
        context.fillPath()
        context.setLineWidth(1.55)
        context.addArc(center: CGPoint(x: 14.0, y: 11.9), radius: 4.1, startAngle: -0.62, endAngle: 0.62, clockwise: false)
        context.strokePath()
    }
    writePNG(rep, to: path)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    controlCenterIcon(selected: false, scale: scale, path: "\(root)/ControlCenter/Resources/sound-vibration\(suffix).png")
    controlCenterIcon(selected: true, scale: scale, path: "\(root)/ControlCenter/Resources/sound-vibration-off\(suffix).png")
    preferenceIcon(scale: scale, path: "\(root)/Preferences/Resources/icon\(suffix).png")
}
