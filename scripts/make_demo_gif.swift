import AppKit
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = root.appendingPathComponent("media/focuslens-demo.gif")
let sourceCandidates = [
    URL(fileURLWithPath: "/tmp/focuslens-current-secondary.png"),
    URL(fileURLWithPath: "/tmp/focuslens-capture-display-2.png"),
    URL(fileURLWithPath: "/tmp/focuslens-capture-display-1.png")
]

guard let sourceURL = sourceCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
      let source = NSImage(contentsOf: sourceURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("No source screenshot found. Capture the secondary display first, then rerun this script.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let width = 960
let height = 540
let canvas = CGRect(x: 0, y: 0, width: width, height: height)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ciContext = CIContext(options: nil)
let blurredSourceCG: CGImage? = {
    let input = CIImage(cgImage: sourceCG)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(1.2, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
    return ciContext.createCGImage(output, from: input.extent)
}()

// Current secondary-display demo target: GitHub left filter row "Repositories 13.6k".
let selection = CGRect(x: 5, y: 400, width: 136, height: 18)
let zoomTarget = CGRect(x: 165, y: 228, width: 630, height: 84)

func imageContext() -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create bitmap context")
    }
    context.interpolationQuality = .high
    return context
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawBase(_ context: CGContext, scale: CGFloat = 1, tx: CGFloat = 0, ty: CGFloat = 0, image: CGImage = sourceCG) {
    let destination = CGRect(x: tx, y: ty, width: canvas.width * scale, height: canvas.height * scale)
    context.draw(image, in: destination)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

func easeInOut(_ t: CGFloat) -> CGFloat {
    t * t * (3 - 2 * t)
}

func interpolatedRect(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
    CGRect(
        x: lerp(from.minX, to.minX, progress),
        y: lerp(from.minY, to.minY, progress),
        width: lerp(from.width, to.width, progress),
        height: lerp(from.height, to.height, progress)
    )
}

func zoomTransform(for rect: CGRect, target: CGRect, progress: CGFloat) -> (scale: CGFloat, tx: CGFloat, ty: CGFloat) {
    let finalScale = min(target.width / rect.width, target.height / rect.height)
    let scale = lerp(1, finalScale, progress)
    let rectCenter = CGPoint(x: rect.midX, y: rect.midY)
    let targetCenter = CGPoint(x: target.midX, y: target.midY)
    let finalTx = targetCenter.x - rectCenter.x * finalScale
    let finalTy = targetCenter.y - rectCenter.y * finalScale
    return (
        scale: scale,
        tx: lerp(0, finalTx, progress),
        ty: lerp(0, finalTy, progress)
    )
}

func drawMaskAndBorder(_ context: CGContext, rect: CGRect, maskAlpha: CGFloat, rainbowPhase: CGFloat) {
    for layer in [
        (inset: CGFloat(-18), alpha: CGFloat(0.08)),
        (inset: CGFloat(-12), alpha: CGFloat(0.12)),
        (inset: CGFloat(-7), alpha: CGFloat(0.18))
    ] {
        let glowRect = rect.insetBy(dx: layer.inset, dy: layer.inset)
        context.saveGState()
        context.addPath(roundedPath(glowRect, radius: 18 + abs(layer.inset)))
        context.addPath(roundedPath(rect, radius: 12))
        context.clip(using: .evenOdd)
        context.setFillColor(NSColor(calibratedWhite: 1, alpha: layer.alpha).cgColor)
        context.fill(canvas)
        context.restoreGState()
    }

    let outer = rect.insetBy(dx: -4, dy: -4)
    let inner = rect.insetBy(dx: 4, dy: 4)
    context.saveGState()
    context.addPath(roundedPath(outer, radius: 16))
    context.addPath(roundedPath(inner, radius: 8))
    context.clip(using: .evenOdd)

    let stops: [CGFloat] = [0, 0.14, 0.28, 0.42, 0.58, 0.74, 0.90, 1]
    let colors = stops.map { stop in
        NSColor(
            calibratedHue: (stop + rainbowPhase).truncatingRemainder(dividingBy: 1),
            saturation: 0.82,
            brightness: 1,
            alpha: 1
        ).cgColor
    } as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: stops) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: outer.minX, y: outer.minY),
            end: CGPoint(x: outer.maxX, y: outer.maxY),
            options: []
        )
    }
    context.restoreGState()
}

func drawFocusScene(
    _ context: CGContext,
    rect: CGRect,
    scale: CGFloat,
    tx: CGFloat,
    ty: CGFloat,
    maskAlpha: CGFloat,
    rainbowPhase: CGFloat,
    title: String
) {
    drawBase(context, scale: scale, tx: tx, ty: ty, image: blurredSourceCG ?? sourceCG)
    context.setFillColor(CGColor(gray: 0, alpha: maskAlpha))
    context.fill(canvas)

    context.saveGState()
    context.addPath(roundedPath(rect, radius: 12))
    context.clip()
    drawBase(context, scale: scale, tx: tx, ty: ty, image: sourceCG)
    context.restoreGState()

    drawMaskAndBorder(context, rect: rect, maskAlpha: maskAlpha, rainbowPhase: rainbowPhase)
    drawTitle(title, context: context)
}

func drawTitle(_ text: String, context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 23, weight: .semibold),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor(calibratedWhite: 0, alpha: 0.32)
    ]
    NSAttributedString(string: "  \(text)  ", attributes: attributes).draw(at: CGPoint(x: 28, y: 488))
    NSGraphicsContext.restoreGraphicsState()
}

func makeFrame(step: Int) -> CGImage {
    let context = imageContext()

    switch step {
    case 0...4:
        drawBase(context)
        drawTitle("Control + W", context: context)

    case 5...10:
        let p = easeInOut(CGFloat(step - 5) / 5)
        let dragRect = CGRect(
            x: selection.minX,
            y: selection.minY,
            width: max(1, selection.width * p),
            height: max(1, selection.height * p)
        )
        drawFocusScene(context, rect: dragRect, scale: 1, tx: 0, ty: 0, maskAlpha: 0.36, rainbowPhase: 0, title: "Drag over Repositories 13.6k")

    case 11...20:
        let p = easeInOut(CGFloat(step - 11) / 9)
        let transform = zoomTransform(for: selection, target: zoomTarget, progress: p)
        let currentRect = interpolatedRect(from: selection, to: zoomTarget, progress: p)
        drawFocusScene(context, rect: currentRect, scale: transform.scale, tx: transform.tx, ty: transform.ty, maskAlpha: 0.46, rainbowPhase: CGFloat(step % 10) / 10, title: "Zoom in")

    case 21...26:
        let transform = zoomTransform(for: selection, target: zoomTarget, progress: 1)
        drawFocusScene(context, rect: zoomTarget, scale: transform.scale, tx: transform.tx, ty: transform.ty, maskAlpha: 0.46, rainbowPhase: CGFloat(step % 10) / 10, title: "Focused")

    case 27...35:
        let p = 1 - easeInOut(CGFloat(step - 27) / 8)
        let transform = zoomTransform(for: selection, target: zoomTarget, progress: p)
        let currentRect = interpolatedRect(from: selection, to: zoomTarget, progress: p)
        drawFocusScene(context, rect: currentRect, scale: transform.scale, tx: transform.tx, ty: transform.ty, maskAlpha: 0.46 * p, rainbowPhase: CGFloat(step % 10) / 10, title: "Esc restores")

    default:
        drawBase(context)
    }

    guard let image = context.makeImage() else {
        fatalError("Could not create frame")
    }
    return image
}

let frameCount = 40
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    fatalError("Could not create GIF destination")
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
    ]
] as CFDictionary)

for step in 0..<frameCount {
    let delay: Double
    switch step {
    case 0...4: delay = 0.22
    case 21...26: delay = 0.16
    case 36...39: delay = 0.24
    default: delay = 0.055
    }
    CGImageDestinationAddImage(destination, makeFrame(step: step), [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay
        ]
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write GIF")
}

print("Wrote \(outputURL.path)")
