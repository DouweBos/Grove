// History/List/CommitDrawing.swift
// GroveUIKit
//
// What a commit row draws: graph lanes and dot, ref labels, avatar and symbols, straight into the row's context.

#if os(macOS)
import AppKit
import GroveKit

@MainActor
struct CommitDrawing {
    let palette: CommitListPalette
    let metrics: CommitListMetrics
    let symbols: SymbolImages

    // MARK: Graph

    /// Pass-through lines span the row; incoming end at the dot, outgoing start at it; lane changes bend in an S.
    func graph(_ node: GraphNode, height: CGFloat, isHead: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let mid = height / 2
        context.setLineWidth(metrics.lineWidth)
        context.setLineCap(.round)
        for line in node.lines {
            let fromX = metrics.laneCenter(line.fromColumn)
            let toX = metrics.laneCenter(line.toColumn)
            let path = CGMutablePath()
            switch line.kind {
            case .passThrough:
                path.move(to: CGPoint(x: fromX, y: 0))
                path.addLine(to: CGPoint(x: toX, y: height))
            case .incoming:
                path.move(to: CGPoint(x: fromX, y: 0))
                curve(path, from: CGPoint(x: fromX, y: 0), to: CGPoint(x: toX, y: mid))
            case .outgoing:
                path.move(to: CGPoint(x: fromX, y: mid))
                curve(path, from: CGPoint(x: fromX, y: mid), to: CGPoint(x: toX, y: height))
            }
            context.setStrokeColor(palette.lane(line.colorIndex).cgColor)
            context.addPath(path)
            context.strokePath()
        }
        let d = metrics.dotDiameter
        let rect = CGRect(x: metrics.laneCenter(node.column) - d / 2, y: mid - d / 2, width: d, height: d)
        if isHead {
            context.setFillColor(palette.accent.cgColor)
            context.fillEllipse(in: rect.insetBy(dx: -1, dy: -1))
        } else if node.isMerge {
            // Hollow marks a merge; the surface fill hides the lines converging behind it.
            context.setFillColor(palette.surface.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(palette.lane(node.colorIndex).cgColor)
            context.setLineWidth(metrics.lineWidth)
            context.strokeEllipse(in: rect.insetBy(dx: metrics.lineWidth / 2, dy: metrics.lineWidth / 2))
        } else {
            context.setFillColor(palette.lane(node.colorIndex).cgColor)
            context.fillEllipse(in: rect)
        }
    }

    /// Continues the next commit's lanes through a row that isn't a commit, such as a day's header.
    func passThrough(_ lanes: [GraphLine], height: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineWidth(metrics.lineWidth)
        for line in lanes {
            let x = metrics.laneCenter(line.fromColumn)
            context.setStrokeColor(palette.lane(line.colorIndex).cgColor)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: height))
            context.strokePath()
        }
    }

    private func curve(_ path: CGMutablePath, from start: CGPoint, to end: CGPoint) {
        guard start.x != end.x else { return path.addLine(to: end) }
        let midY = (start.y + end.y) / 2
        path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
    }

    // MARK: Refs

    /// Up to two labels, then "+N"; returns where the subject starts.
    func refs(_ refs: [CommitDisplayRef], x: CGFloat, midY: CGFloat, maxX: CGFloat) -> CGFloat {
        var x = x
        let gap = 4 * metrics.scale
        for ref in refs.prefix(2) {
            guard x < maxX - 40 * metrics.scale else { break }
            x = label(ref, x: x, midY: midY, maxX: maxX) + gap
        }
        if refs.count > 2 {
            x = capsule("+\(refs.count - 2)", symbol: nil, color: palette.secondary, fill: palette.secondary, x: x,
                        midY: midY, maxX: maxX, font: metrics.font(11, .semibold)) + gap
        }
        return x
    }

    private func label(_ ref: CommitDisplayRef, x: CGFloat, midY: CGFloat, maxX: CGFloat) -> CGFloat {
        let symbol = switch ref.kind {
        case .local(let isHEAD): isHEAD ? "checkmark" : "arrow.triangle.branch"
        case .remote: "cloud"
        case .tag: "tag"
        }
        let color = palette.color(ref.kind)
        return capsule(ref.name, symbol: symbol, trailing: ref.isOnRemote ? "cloud" : nil, color: color, fill: color, x: x,
                       midY: midY, maxX: maxX, font: metrics.font(11, .semibold))
    }

    /// A tinted capsule with an optional symbol either side of a name that truncates in the middle.
    func capsule(_ text: String, symbol: String?, trailing: String? = nil, color: NSColor, fill: NSColor, x: CGFloat,
                 midY: CGFloat, maxX: CGFloat, font: NSFont) -> CGFloat {
        let s = metrics.scale
        let symbolSize = 9 * s
        let lead = symbol.flatMap { image($0, size: symbolSize, color: color) }
        let trail = trailing.flatMap { image($0, size: symbolSize, color: color) }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: Self.middle]
        let textWidth = ceil((text as NSString).size(withAttributes: attrs).width)
        let padding = 7 * s
        let fixed = padding * 2 + (lead.map { $0.size.width + 3 * s } ?? 0) + (trail.map { $0.size.width + 3 * s } ?? 0)
        let nameWidth = max(0, min(textWidth, metrics.refNameWidth, maxX - x - fixed))
        let height = ceil(font.ascender - font.descender) + 4 * s
        let rect = NSRect(x: x, y: midY - height / 2, width: fixed + nameWidth, height: height)
        fill.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        var cursor = rect.minX + padding
        if let lead {
            lead.draw(in: NSRect(x: cursor, y: midY - lead.size.height / 2, width: lead.size.width, height: lead.size.height))
            cursor += lead.size.width + 3 * s
        }
        let textHeight = ceil(font.ascender - font.descender)
        (text as NSString).draw(with: NSRect(x: cursor, y: midY - textHeight / 2, width: nameWidth, height: textHeight),
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        cursor += nameWidth + 3 * s
        if let trail {
            trail.draw(in: NSRect(x: cursor, y: midY - trail.size.height / 2, width: trail.size.width, height: trail.size.height))
        }
        return rect.maxX
    }

    // MARK: Avatar

    func avatar(_ commit: CommitInfo, image: NSImage?, tint: NSColor?, in rect: NSRect) {
        let circle = NSBezierPath(ovalIn: rect)
        if let image {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let color = tint ?? palette.lane(AvatarInitials.colorIndex(commit.authorEmail))
            color.withAlphaComponent(0.18).setFill()
            circle.fill()
            let font = NSFont.systemFont(ofSize: rect.height * 0.39, weight: .semibold).rounded
            let initials = AvatarInitials.of(commit.authorName) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = initials.size(withAttributes: attrs)
            initials.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
        palette.border.setStroke()
        let border = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        border.lineWidth = 0.5
        border.stroke()
    }

    // MARK: Text and symbols

    func text(_ string: String, font: NSFont, color: NSColor, in rect: NSRect, truncation: NSLineBreakMode = .byTruncatingTail) {
        let style = truncation == .byTruncatingTail ? Self.tail : Self.middle
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let height = ceil(font.ascender - font.descender)
        (string as NSString).draw(with: NSRect(x: rect.minX, y: rect.midY - height / 2, width: max(0, rect.width), height: height),
                                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Draws a symbol centred on `midY` ending at `maxX`; returns where it starts.
    @discardableResult
    func symbol(_ name: String, size: CGFloat, color: NSColor, maxX: CGFloat, midY: CGFloat) -> CGFloat {
        guard let image = image(name, size: size, color: color) else { return maxX }
        let rect = NSRect(x: maxX - image.size.width, y: midY - image.size.height / 2, width: image.size.width,
                          height: image.size.height)
        image.draw(in: rect)
        return rect.minX
    }

    func image(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        symbols.image(name, size: size, color: color)
    }

    static let tail: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    static let middle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        return style
    }()
}

/// Tinted SF Symbols, made once per table rather than per row drawn.
@MainActor
final class SymbolImages {
    private var images: [String: NSImage] = [:]

    func image(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let key = "\(name)|\(size)|\(ObjectIdentifier(color).hashValue)"
        if let cached = images[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        if images.count > 200 { images.removeAll() }
        images[key] = image
        return image
    }
}

extension NSFont {
    var rounded: NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
#endif
