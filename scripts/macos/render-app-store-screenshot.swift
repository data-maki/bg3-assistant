import AppKit
import Foundation

private let arguments = CommandLine.arguments
guard arguments.count == 8, let panelWidth = Double(arguments[7]) else {
    fputs("Usage: render-app-store-screenshot <source> <output> <number> <title> <detail-one> <detail-two> <panel-width>\n", stderr)
    exit(2)
}

let sourcePath = arguments[1]
let outputPath = arguments[2]
let number = arguments[3]
let title = arguments[4]
let detailOne = arguments[5]
let detailTwo = arguments[6]

guard let sourceData = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)),
      let sourceRepresentation = NSBitmapImageRep(data: sourceData) else {
    fputs("Could not read source screenshot: \(sourcePath)\n", stderr)
    exit(1)
}

let width = 1_440
let height = 900
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create screenshot canvas.\n", stderr)
    exit(1)
}
bitmap.size = NSSize(width: width, height: height)

func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

func font(family: String, size: CGFloat, bold: Bool = false) -> NSFont {
    let traits: NSFontTraitMask = bold ? .boldFontMask : []
    return NSFontManager.shared.font(
        withFamily: family,
        traits: traits,
        weight: bold ? 8 : 5,
        size: size
    ) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
}

func drawText(
    _ text: String,
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    height textHeight: CGFloat,
    font: NSFont,
    color: NSColor,
    kerning: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: kerning,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(
        with: NSRect(x: x, y: CGFloat(height) - top - textHeight, width: width, height: textHeight),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

NSGraphicsContext.saveGraphicsState()
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create screenshot graphics context.\n", stderr)
    exit(1)
}
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high

let background = NSGradient(colors: [color(29, 20, 16), color(8, 7, 7)])!
background.draw(
    from: NSPoint(x: 0, y: height),
    to: NSPoint(x: width, y: 0),
    options: []
)

color(155, 103, 66, alpha: 0.70).setFill()
NSRect(x: 88, y: height - 95, width: 520, height: 1).fill()

drawText(
    "BG3 OVERLAY",
    x: 88,
    top: 58,
    width: 520,
    height: 28,
    font: font(family: "Avenir Next", size: 18, bold: true),
    color: color(201, 151, 106),
    kerning: 1.8
)
drawText(
    title,
    x: 88,
    top: 168,
    width: 650,
    height: 70,
    font: font(family: "Avenir Next Condensed", size: 48, bold: true),
    color: color(244, 237, 229),
    kerning: 0.4
)

color(181, 120, 73).setFill()
NSRect(x: 88, y: height - 364, width: 4, height: 112).fill()
drawText(
    detailOne,
    x: 112,
    top: 258,
    width: 640,
    height: 34,
    font: font(family: "Avenir Next", size: 23),
    color: color(216, 205, 194)
)
drawText(
    detailTwo,
    x: 112,
    top: 298,
    width: 640,
    height: 34,
    font: font(family: "Avenir Next", size: 23),
    color: color(216, 205, 194)
)

drawText(
    number,
    x: 88,
    top: 690,
    width: 180,
    height: 118,
    font: font(family: "Avenir Next Condensed", size: 96, bold: true),
    color: color(155, 103, 66)
)
drawText(
    "NATIVE macOS OVERLAY",
    x: 90,
    top: 822,
    width: 300,
    height: 24,
    font: font(family: "Avenir Next", size: 16, bold: true),
    color: color(143, 129, 119),
    kerning: 1.1
)

let sourceWidth = CGFloat(sourceRepresentation.pixelsWide)
let sourceHeight = CGFloat(sourceRepresentation.pixelsHigh)
let renderedPanelWidth = CGFloat(panelWidth)
let renderedPanelHeight = sourceHeight * renderedPanelWidth / sourceWidth
let border: CGFloat = 12
let framedWidth = renderedPanelWidth + border * 2
let framedHeight = renderedPanelHeight + border * 2
let framedX = CGFloat(width) - framedWidth - 64
let framedY = (CGFloat(height) - framedHeight) / 2
let framedRect = NSRect(x: framedX, y: framedY, width: framedWidth, height: framedHeight)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(43, 33, 29).setFill()
NSBezierPath(roundedRect: framedRect, xRadius: 12, yRadius: 12).fill()
NSGraphicsContext.restoreGraphicsState()

let sourceImage = NSImage(size: NSSize(width: sourceWidth, height: sourceHeight))
sourceImage.addRepresentation(sourceRepresentation)
sourceImage.draw(
    in: NSRect(
        x: framedX + border,
        y: framedY + border,
        width: renderedPanelWidth,
        height: renderedPanelHeight
    ),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode screenshot PNG.\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("Could not write screenshot: \(error.localizedDescription)\n", stderr)
    exit(1)
}
