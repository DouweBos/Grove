// Renders Grove's app icon into app/Grove/Grove/AppIcon.icon (Icon Composer bundle).
// Usage: swift scripts/render-icon.swift [output .icon path]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Appearance {
    let name: String
    let background: (top: String, bottom: String)
    let glyph: String
}

let light = Appearance(name: "light", background: ("#4ADE80", "#047857"), glyph: "#FFFFFF")
let dark = Appearance(name: "dark", background: ("#14532D", "#052E16"), glyph: "#4ADE80")
let gradientAngle: CGFloat = 20 // degrees off vertical, top-left → bottom-right

// MARK: - Glyph (designed on the 1024 macOS grid, y down, body at 100...924)

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func leaf(from a: CGPoint, to b: CGPoint, width w: CGFloat, roundness k: CGFloat) -> CGPath {
    let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
    let n = point(-dy / len * w, dx / len * w)
    func at(_ t: CGFloat, _ s: CGFloat) -> CGPoint { point(a.x + dx * t + n.x * s, a.y + dy * t + n.y * s) }
    let p = CGMutablePath()
    p.move(to: a)
    p.addCurve(to: b, control1: at(k, 1), control2: at(1 - k, 1))
    p.addCurve(to: a, control1: at(1 - k, -1), control2: at(k, -1))
    p.closeSubpath()
    return p
}

/// A leaf whose cut-out vein branches both ways, like a git branch.
func glyph() -> CGPath {
    let a = point(292, 732), b = point(732, 292)
    // Point along the leaf axis (t) offset sideways by s.
    func at(_ t: CGFloat, _ s: CGFloat) -> CGPoint {
        point(a.x + (b.x - a.x) * t + s * 0.7071, a.y + (b.y - a.y) * t + s * 0.7071)
    }
    let vein = CGMutablePath()
    vein.move(to: at(0.109, 0))
    vein.addLine(to: at(0.768, 0))
    for (t0, side) in [(CGFloat(0.36), CGFloat(1)), (0.52, -1)] {
        vein.move(to: at(t0, 0))
        vein.addCurve(to: at(t0 + 0.141, 110 * side), control1: at(t0 + 0.027, 68 * side), control2: at(t0 + 0.072, 96 * side))
    }
    let cut = vein.copy(strokingWithWidth: 40, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return leaf(from: a, to: b, width: 275, roundness: 0.22).subtracting(cut)
}

// MARK: - Output

func rgb(_ hex: String) -> [CGFloat] {
    var v: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return [CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255]
}

func color(_ hex: String) -> CGColor {
    let c = rgb(hex)
    return CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
}

/// Icon Composer's canvas is the icon body, so the 824 grid body is scaled up to fill 1024.
func writeGlyph(_ appearance: Appearance, to url: URL) throws {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale: CGFloat = 1024 / 824
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -512, y: -512)
    ctx.addPath(glyph())
    ctx.setFillColor(color(appearance.glyph))
    ctx.fillPath()

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

func srgbString(_ hex: String) -> String {
    "srgb:" + (rgb(hex) + [1]).map { String(format: "%.5f", $0) }.joined(separator: ",")
}

func fill(_ appearance: Appearance) -> [String: Any] {
    let dx = 0.5 * sin(gradientAngle * .pi / 180)
    // Decimal keeps the JSON free of float noise.
    func coord(_ v: CGFloat) -> NSDecimalNumber { NSDecimalNumber(string: String(format: "%.3f", v)) }
    return ["linear-gradient": [srgbString(appearance.background.top), srgbString(appearance.background.bottom)],
            "orientation": ["start": ["x": coord(0.5 - dx), "y": 0], "stop": ["x": coord(0.5 + dx), "y": 1]]]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("app/Grove/Grove/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

for appearance in [light, dark] {
    try writeGlyph(appearance, to: assets.appendingPathComponent("glyph-\(appearance.name).png"))
}

let icon: [String: Any] = [
    "fill-specializations": [["value": fill(light)], ["appearance": "dark", "value": fill(dark)]],
    "groups": [[
        "layers": [[
            "name": "glyph",
            "glass": false,
            "image-name-specializations": [["value": "glyph-light.png"], ["appearance": "dark", "value": "glyph-dark.png"]],
        ]],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "specular": false,
        "translucency": ["enabled": false, "value": 0.5],
    ]],
    "supported-platforms": ["squares": ["macOS"]],
]
let json = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys])
try json.write(to: bundle.appendingPathComponent("icon.json"))
print("Wrote \(bundle.path)")
