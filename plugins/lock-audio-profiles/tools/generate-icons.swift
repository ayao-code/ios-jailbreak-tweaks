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

private func soundVibrationStrokes(selected: Bool) -> [(path: CGPath, width: CGFloat)] {
    let vibration = CGMutablePath()
    vibration.move(to: CGPoint(x: 4.5, y: 9))
    for point in [
        CGPoint(x: 2.7, y: 11),
        CGPoint(x: 4.5, y: 13),
        CGPoint(x: 2.7, y: 15),
        CGPoint(x: 4.5, y: 17),
        CGPoint(x: 2.7, y: 19),
        CGPoint(x: 4.5, y: 21)
    ] {
        vibration.addLine(to: point)
    }

    let speaker = CGMutablePath()
    speaker.move(to: CGPoint(x: 8.2, y: 11.3))
    speaker.addLine(to: CGPoint(x: 11.8, y: 11.3))
    speaker.addLine(to: CGPoint(x: 17.2, y: 6.7))
    speaker.addQuadCurve(to: CGPoint(x: 18, y: 7.05), control: CGPoint(x: 18, y: 6.05))
    speaker.addLine(to: CGPoint(x: 18, y: 22.95))
    speaker.addQuadCurve(to: CGPoint(x: 17.2, y: 23.3), control: CGPoint(x: 18, y: 23.95))
    speaker.addLine(to: CGPoint(x: 11.8, y: 18.7))
    speaker.addLine(to: CGPoint(x: 8.2, y: 18.7))
    speaker.addQuadCurve(to: CGPoint(x: 7.5, y: 18), control: CGPoint(x: 7.5, y: 18.7))
    speaker.addLine(to: CGPoint(x: 7.5, y: 12))
    speaker.addQuadCurve(to: CGPoint(x: 8.2, y: 11.3), control: CGPoint(x: 7.5, y: 11.3))
    speaker.closeSubpath()

    let innerSoundWave = CGMutablePath()
    innerSoundWave.move(to: CGPoint(x: 21.4, y: 11.7))
    innerSoundWave.addQuadCurve(to: CGPoint(x: 21.4, y: 18.3), control: CGPoint(x: 24, y: 15))

    let outerSoundWave = CGMutablePath()
    outerSoundWave.move(to: CGPoint(x: 24.3, y: 8.4))
    outerSoundWave.addQuadCurve(to: CGPoint(x: 24.3, y: 21.6), control: CGPoint(x: 29, y: 15))

    var strokes: [(path: CGPath, width: CGFloat)] = [
        (vibration, 1.65),
        (speaker, 1.9),
        (innerSoundWave, 1.85),
        (outerSoundWave, 1.85)
    ]
    if selected {
        let slash = CGMutablePath()
        slash.move(to: CGPoint(x: 6, y: 25))
        slash.addLine(to: CGPoint(x: 23.7, y: 5))
        strokes.append((slash, 2.05))
    }
    return strokes
}

private func controlCenterIcon(strokes: [(path: CGPath, width: CGFloat)], scale: Int, path: String) {
    let rep = withContext(size: 30, scale: scale) { context in
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            context.setLineWidth(stroke.width)
            context.addPath(stroke.path)
            context.strokePath()
        }
    }
    writePNG(rep, to: path)
}

private func controlCenterSVG(strokes: [(path: CGPath, width: CGFloat)], path: String) {
    let elements = strokes.map { stroke in
        var commands: [String] = []
        stroke.path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                commands.append("M\(points[0].x) \(points[0].y)")
            case .addLineToPoint:
                commands.append("L\(points[0].x) \(points[0].y)")
            case .addQuadCurveToPoint:
                commands.append("Q\(points[0].x) \(points[0].y) \(points[1].x) \(points[1].y)")
            case .addCurveToPoint:
                commands.append("C\(points[0].x) \(points[0].y) \(points[1].x) \(points[1].y) \(points[2].x) \(points[2].y)")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                fatalError("Unsupported path element")
            }
        }
        return "    <path d=\"\(commands.joined(separator: " "))\" stroke-width=\"\(stroke.width)\"/>"
    }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 30 30">
      <g transform="translate(0 30) scale(1 -1)" fill="none" stroke="#000" stroke-linecap="round" stroke-linejoin="round">
    \(elements.joined(separator: "\n"))
      </g>
    </svg>

    """
    try! svg.write(toFile: path, atomically: true, encoding: .utf8)
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
let normalStrokes = soundVibrationStrokes(selected: false)
let selectedStrokes = soundVibrationStrokes(selected: true)
controlCenterSVG(strokes: normalStrokes, path: "\(root)/ControlCenter/Resources/sound-vibration.svg")
controlCenterSVG(strokes: selectedStrokes, path: "\(root)/ControlCenter/Resources/sound-vibration-off.svg")
for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    controlCenterIcon(strokes: normalStrokes, scale: scale, path: "\(root)/ControlCenter/Resources/sound-vibration\(suffix).png")
    controlCenterIcon(strokes: selectedStrokes, scale: scale, path: "\(root)/ControlCenter/Resources/sound-vibration-off\(suffix).png")
    preferenceIcon(scale: scale, path: "\(root)/Preferences/Resources/icon\(suffix).png")
}
