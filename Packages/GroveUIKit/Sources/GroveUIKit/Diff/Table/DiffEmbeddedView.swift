// Diff/Table/DiffEmbeddedView.swift
// GroveUIKit
//
// A diff as tall as itself inside the app's scroll view. The table's own scroll view covers only the part
// on screen and scrolls along, so it still only makes the rows that show.

#if os(macOS)
import AppKit

final class DiffEmbeddedView: NSView {
    private let scroll: NSScrollView
    private var observed: [NSView] = []
    private var isSyncing = false
    var onSync: (() -> Void)?

    init(scroll: NSScrollView) {
        self.scroll = scroll
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        follow()
        needsLayout = true
    }

    /// Anything above scrolling or moving changes which part is on screen.
    private func follow() {
        let center = NotificationCenter.default
        for view in observed {
            center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: view)
            center.removeObserver(self, name: NSView.frameDidChangeNotification, object: view)
        }
        observed = []
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                center.addObserver(self, selector: #selector(sync), name: NSView.boundsDidChangeNotification, object: clip)
            }
            if view.postsFrameChangedNotifications {
                center.addObserver(self, selector: #selector(sync), name: NSView.frameDidChangeNotification, object: view)
            }
            observed.append(view)
            ancestor = view.superview
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sync()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        sync()
    }

    override func layout() {
        super.layout()
        sync()
    }

    @objc func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let onScreen = window == nil ? NSRect.zero : visibleRect.intersection(bounds)
        let top = onScreen.isEmpty ? 0 : onScreen.minY
        let frame = NSRect(x: 0, y: top, width: bounds.width, height: onScreen.isEmpty ? 0 : onScreen.height)
        if scroll.frame != frame { scroll.frame = frame }
        let clip = scroll.contentView
        if clip.bounds.minY != top {
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: top))
            scroll.reflectScrolledClipView(clip)
        }
        onSync?()
    }
}

/// Sideways scrolling is the diff's; up and down is the app's scroll view's.
final class DiffEmbeddedScrollView: NSScrollView {
    private var scrollsSideways: Bool?

    override func scrollWheel(with event: NSEvent) {
        let x = abs(event.scrollingDeltaX)
        let y = abs(event.scrollingDeltaY)
        // A gesture keeps the direction it started in.
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            scrollsSideways = nil
        }
        if scrollsSideways == nil, x > 0 || y > 0 { scrollsSideways = x > y }
        if scrollsSideways == true {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}
#endif
