import AppKit

// MARK: - Region Picker

/// Shows a single transparent fullscreen panel spanning all displays.
/// The user drags to define a rectangle (like the macOS screenshot tool).
/// Calls `completion` on the main thread with the selected rect in global
/// NSScreen coordinates (origin bottom-left), or `nil` on Esc / too-small drag.
final class RegionPickerWindowController: NSObject {
    private var panel: NSPanel?
    private var completion: ((CGRect?) -> Void)?
    private var finished = false   // guard against double-fire

    func show(completion: @escaping (CGRect?) -> Void) {
        guard panel == nil else { return }
        self.completion = completion
        finished = false

        // One panel that covers the union of every connected screen.
        var unionRect = CGRect.null
        for screen in NSScreen.screens { unionRect = unionRect.union(screen.frame) }
        if unionRect.isNull { unionRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080) }

        let p = NSPanel(
            contentRect: unionRect,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        p.level              = .screenSaver
        p.isOpaque           = false
        p.hasShadow          = false
        p.backgroundColor    = .clear
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        p.acceptsMouseMovedEvents = true

        let view = RegionOverlayView(
            frame: CGRect(origin: .zero, size: unionRect.size),
            controller: self
        )
        p.contentView = view
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(view)
        panel = p
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Called by overlay

    func didSelectRegion(_ rect: CGRect) { finish(result: rect) }
    func didCancel()                     { finish(result: nil)  }

    // MARK: - Private

    private func finish(result: CGRect?) {
        guard !finished else { return }
        finished = true
        let cb = completion
        completion = nil

        // Disable input immediately (safe to call synchronously).
        panel?.ignoresMouseEvents = true

        // Capture the panel into a local so our stored property can be cleared.
        // Then defer hide + callback to the NEXT run-loop iteration so the
        // current mouse-event handler returns to AppKit before we touch the window.
        let p = panel
        panel = nil
        DispatchQueue.main.async {
            p?.orderOut(nil)    // just hide — no close(); let ARC free the window
            cb?(result)
        }
    }
}

// MARK: - Overlay View

private final class RegionOverlayView: NSView {
    private weak var controller: RegionPickerWindowController?

    private var dragStart: CGPoint?
    private var selectionRect: CGRect = .zero
    private let handleSize: CGFloat = 6

    required init?(coder: NSCoder) { fatalError() }

    init(frame: CGRect, controller: RegionPickerWindowController) {
        self.controller = controller
        super.init(frame: frame)
    }

    override var acceptsFirstResponder: Bool { true }

    // window is nil during init; become first responder once we have a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dim overlay
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.fill(bounds)

        if dragStart != nil {
            let sel = normalized(selectionRect)
            ctx.clear(sel)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
            ctx.fill(sel)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.setLineWidth(1.5)
            ctx.stroke(sel)
            drawHandles(sel, ctx: ctx)
            drawSizeLabel(sel)
        } else {
            drawHint()
        }
    }

    private func drawHandles(_ r: CGRect, ctx: CGContext) {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for pt in [r.origin,
                   CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.minX, y: r.maxY),
                   CGPoint(x: r.maxX, y: r.maxY)] {
            ctx.fillEllipse(in: CGRect(
                x: pt.x - handleSize / 2, y: pt.y - handleSize / 2,
                width: handleSize, height: handleSize))
        }
    }

    private func drawSizeLabel(_ sel: CGRect) {
        let text = "\(Int(sel.width)) × \(Int(sel.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let ns  = NSAttributedString(string: text, attributes: attrs)
        let sz  = ns.size()
        let pad: CGFloat = 4
        var bg = CGRect(
            x: sel.midX - sz.width / 2 - pad,
            y: sel.minY - sz.height - 12,
            width: sz.width + pad * 2, height: sz.height + pad * 2
        )
        if bg.minY < 2 { bg.origin.y = sel.maxY + 4 }
        bg.origin.x = max(2, min(bg.origin.x, bounds.maxX - bg.width - 2))

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
        ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        ns.draw(at: CGPoint(x: bg.minX + pad, y: bg.minY + pad))
    }

    private func drawHint() {
        let text = "Drag to select a recording area    Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let sz = ns.size()
        ns.draw(at: CGPoint(x: (bounds.width  - sz.width)  / 2,
                            y: (bounds.height - sz.height) / 2))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        dragStart     = event.locationInWindow
        selectionRect = CGRect(origin: dragStart!, size: .zero)
        needsDisplay  = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = dragStart else { return }
        let c = event.locationInWindow
        selectionRect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                               width: abs(c.x - s.x), height: abs(c.y - s.y))
        needsDisplay  = true
    }

    override func mouseUp(with event: NSEvent) {
        let sel = normalized(selectionRect)
        guard sel.width > 10, sel.height > 10 else {
            controller?.didCancel()
            return
        }
        // Convert from panel-local → global NSScreen coordinates.
        let origin = window?.frame.origin ?? .zero
        let globalRect = CGRect(
            x: origin.x + sel.minX, y: origin.y + sel.minY,
            width: sel.width, height: sel.height
        )
        controller?.didSelectRegion(globalRect)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.didCancel() }  // Escape
    }

    // MARK: Helpers

    private func normalized(_ r: CGRect) -> CGRect {
        CGRect(x: min(r.minX, r.maxX), y: min(r.minY, r.maxY),
               width: abs(r.width), height: abs(r.height))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

