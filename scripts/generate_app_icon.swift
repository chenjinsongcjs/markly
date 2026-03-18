import AppKit

struct Palette {
    static let midnight = NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.18, alpha: 1)
    static let ocean = NSColor(calibratedRed: 0.08, green: 0.37, blue: 0.43, alpha: 1)
    static let cyan = NSColor(calibratedRed: 0.35, green: 0.82, blue: 0.82, alpha: 1)
    static let cream = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.90, alpha: 1)
    static let paper = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.94, alpha: 1)
    static let fold = NSColor(calibratedRed: 0.94, green: 0.89, blue: 0.82, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.26, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.99, green: 0.69, blue: 0.28, alpha: 1)
    static let mist = NSColor(calibratedRed: 0.75, green: 0.89, blue: 0.92, alpha: 0.18)
}

func roundedRectPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillBackground(in rect: NSRect) {
    let background = roundedRectPath(rect.insetBy(dx: 52, dy: 52), radius: 186)
    background.addClip()

    let gradient = NSGradient(colors: [Palette.midnight, Palette.ocean])!
    gradient.draw(in: background, angle: -55)

    let glowCenter = NSPoint(x: rect.midX - 170, y: rect.maxY - 200)
    let glow = NSGradient(colorsAndLocations:
        (Palette.cyan.withAlphaComponent(0.42), 0.0),
        (Palette.cyan.withAlphaComponent(0.0), 1.0)
    )!
    glow.draw(fromCenter: glowCenter, radius: 20, toCenter: glowCenter, radius: 430, options: [])

    let halo = roundedRectPath(NSRect(x: 168, y: 118, width: 688, height: 688), radius: 180)
    Palette.mist.setFill()
    halo.fill()

    let speck1 = NSBezierPath(ovalIn: NSRect(x: 176, y: 760, width: 148, height: 148))
    Palette.cyan.withAlphaComponent(0.12).setFill()
    speck1.fill()

    let speck2 = NSBezierPath(ovalIn: NSRect(x: 742, y: 182, width: 104, height: 104))
    Palette.accent.withAlphaComponent(0.13).setFill()
    speck2.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    let strokePath = roundedRectPath(rect.insetBy(dx: 52, dy: 52), radius: 186)
    strokePath.lineWidth = 4
    Palette.cream.withAlphaComponent(0.16).setStroke()
    strokePath.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func drawDocumentCard() {
    NSGraphicsContext.current?.saveGraphicsState()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -26)
    shadow.shadowBlurRadius = 50
    shadow.set()

    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 512)
    transform.rotate(byDegrees: -10)
    transform.translateX(by: -512, yBy: -512)
    transform.concat()

    let cardRect = NSRect(x: 242, y: 160, width: 540, height: 704)
    let cardPath = roundedRectPath(cardRect, radius: 74)
    Palette.paper.setFill()
    cardPath.fill()

    let cardGradient = NSGradient(colors: [
        Palette.paper,
        Palette.cream
    ])!
    cardGradient.draw(in: cardPath, angle: -90)

    cardPath.lineWidth = 2
    Palette.ink.withAlphaComponent(0.08).setStroke()
    cardPath.stroke()

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: 654, y: 864))
    foldPath.line(to: NSPoint(x: 782, y: 736))
    foldPath.line(to: NSPoint(x: 782, y: 864))
    foldPath.close()
    Palette.fold.setFill()
    foldPath.fill()

    let foldHighlight = NSBezierPath()
    foldHighlight.move(to: NSPoint(x: 674, y: 864))
    foldHighlight.line(to: NSPoint(x: 782, y: 756))
    foldHighlight.line(to: NSPoint(x: 782, y: 864))
    foldHighlight.close()
    Palette.cream.withAlphaComponent(0.72).setFill()
    foldHighlight.fill()

    let badgeRect = NSRect(x: 306, y: 720, width: 170, height: 84)
    let badgePath = roundedRectPath(badgeRect, radius: 30)
    let badgeGradient = NSGradient(colors: [
        Palette.accent,
        Palette.accent.blended(withFraction: 0.28, of: Palette.cream) ?? Palette.accent
    ])!
    badgeGradient.draw(in: badgePath, angle: -90)

    let hashAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44, weight: .bold),
        .foregroundColor: Palette.ink
    ]
    let hash = NSAttributedString(string: "#", attributes: hashAttributes)
    hash.draw(at: NSPoint(x: 368, y: 736))

    let mark = NSBezierPath()
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.lineWidth = 54
    mark.move(to: NSPoint(x: 350, y: 330))
    mark.line(to: NSPoint(x: 350, y: 614))
    mark.line(to: NSPoint(x: 482, y: 432))
    mark.line(to: NSPoint(x: 606, y: 614))
    mark.line(to: NSPoint(x: 606, y: 330))
    Palette.ink.setStroke()
    mark.stroke()

    let accentStroke = NSBezierPath()
    accentStroke.lineCapStyle = .round
    accentStroke.lineJoinStyle = .round
    accentStroke.lineWidth = 24
    accentStroke.move(to: NSPoint(x: 650, y: 600))
    accentStroke.line(to: NSPoint(x: 708, y: 542))
    accentStroke.line(to: NSPoint(x: 650, y: 484))
    Palette.cyan.setStroke()
    accentStroke.stroke()

    for (index, width, alpha) in [(0, 292.0, 0.20), (1, 248.0, 0.14), (2, 184.0, 0.12)] {
        let lineRect = NSRect(x: 308, y: 248 - CGFloat(index) * 52, width: width, height: 18)
        let linePath = roundedRectPath(lineRect, radius: 9)
        Palette.ink.withAlphaComponent(alpha).setFill()
        linePath.fill()
    }

    let highlightRect = NSRect(x: 308, y: 248, width: 116, height: 18)
    let highlight = roundedRectPath(highlightRect, radius: 9)
    Palette.accent.withAlphaComponent(0.75).setFill()
    highlight.fill()

    NSGraphicsContext.current?.restoreGraphicsState()
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    fillBackground(in: NSRect(x: 0, y: 0, width: size, height: size))
    drawDocumentCard()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }

    try pngData.write(to: url)
}

let args = CommandLine.arguments
let outputDirectory = args.count > 1 ? URL(fileURLWithPath: args[1], isDirectory: true) : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let image = renderIcon(size: 1024)
let outputURL = outputDirectory.appendingPathComponent("icon_1024.png")
try writePNG(image, to: outputURL)
print(outputURL.path)
