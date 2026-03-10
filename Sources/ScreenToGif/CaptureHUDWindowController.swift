import AppKit
import SwiftUI

// MARK: - Transparent NSHostingView
// NSHostingView by default renders a white/gray background layer which causes
// a visible "stroke" around any shaped SwiftUI background. This subclass keeps
// the hosting view's own layer fully transparent.
private final class TransparentHostingView<V: View>: NSHostingView<V> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
    override var isOpaque: Bool { false }
}

// MARK: - Zone resize view (marching-ants border + draggable handles)

/// Eight resize handles around the zone border.  Dragging a handle resizes the
/// zone in screen coordinates; the callback returns the new global CGRect.
private final class ZoneResizeView: NSView {

    /// Called on every drag step with the new screen-space rect.
    var onResize: ((CGRect) -> Void)?

    // MARK: Handle geometry
    private enum Handle: CaseIterable {
        case topLeft, top, topRight
        case left,          right
        case bottomLeft, bottom, bottomRight
    }
    /// Hit-test radius around each handle centre (generous for touch accuracy).
    private static let hitR: CGFloat = 14
    /// Drawn size of the square handle knob.
    private static let knobS: CGFloat = 10

    // MARK: Animation
    private var dashPhase: CGFloat = 0
    private var animTimer: Timer?

    // MARK: Drag state
    private var activeHandle: Handle?
    private var dragStartMouse  = CGPoint.zero  // in window coords at drag start
    private var dragStartRect   = CGRect.zero   // zone window frame at drag start

    // MARK: Init
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dashPhase -= 1.0
            if self.dashPhase < -13 { self.dashPhase = 0 }
            self.setNeedsDisplay(self.bounds)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { animTimer?.invalidate() }

    override var isFlipped:         Bool { false }
    override var isOpaque:          Bool { false }
    // Must accept mouse events (window has ignoresMouseEvents = false now).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Handle positions (in view coords, origin bottom-left)
    private func handleCentre(_ h: Handle) -> CGPoint {
        let b = bounds
        switch h {
        case .topLeft:     return CGPoint(x: b.minX, y: b.maxY)
        case .top:         return CGPoint(x: b.midX, y: b.maxY)
        case .topRight:    return CGPoint(x: b.maxX, y: b.maxY)
        case .left:        return CGPoint(x: b.minX, y: b.midY)
        case .right:       return CGPoint(x: b.maxX, y: b.midY)
        case .bottomLeft:  return CGPoint(x: b.minX, y: b.minY)
        case .bottom:      return CGPoint(x: b.midX, y: b.minY)
        case .bottomRight: return CGPoint(x: b.maxX, y: b.minY)
        }
    }

    private func handle(at viewPt: CGPoint) -> Handle? {
        let r = Self.hitR
        return Handle.allCases.first {
            let c = handleCentre($0)
            return abs(viewPt.x - c.x) <= r && abs(viewPt.y - c.y) <= r
        }
    }

    // MARK: Cursor
    private func cursor(for h: Handle) -> NSCursor {
        switch h {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom:          return .resizeUpDown
        case .left, .right:          return .resizeLeftRight
        }
    }

    // MARK: Mouse events
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let h = handle(at: pt) else { return }
        activeHandle   = h
        dragStartMouse = event.locationInWindow   // window-local
        dragStartRect  = window?.frame ?? .zero   // screen-space frame of zone window
        cursor(for: h).push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let h = activeHandle, let win = window else { return }
        let current = event.locationInWindow
        let dx = current.x - dragStartMouse.x
        let dy = current.y - dragStartMouse.y
        var r = dragStartRect
        let minSz: CGFloat = 40

        switch h {
        case .topLeft:
            r.origin.x    += dx;  r.size.width  -= dx
            r.size.height += dy
        case .top:
            r.size.height += dy
        case .topRight:
            r.size.width  += dx
            r.size.height += dy
        case .left:
            r.origin.x    += dx;  r.size.width  -= dx
        case .right:
            r.size.width  += dx
        case .bottomLeft:
            r.origin.x    += dx;  r.size.width  -= dx
            r.origin.y    += dy;  r.size.height -= dy
        case .bottom:
            r.origin.y    += dy;  r.size.height -= dy
        case .bottomRight:
            r.size.width  += dx
            r.origin.y    += dy;  r.size.height -= dy
        }

        // Clamp minimum size.
        if r.size.width  < minSz { r.size.width  = minSz }
        if r.size.height < minSz { r.size.height = minSz }

        win.setFrame(r, display: true, animate: false)
        // Resize the NSView to match new window content size.
        frame = CGRect(origin: .zero, size: r.size)
        if let cb = onResize {
            let captured = r
            Task { @MainActor in cb(captured) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if activeHandle != nil { NSCursor.pop() }
        activeHandle = nil
    }

    // MARK: Drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let r = bounds.insetBy(dx: 2, dy: 2)

        // Dark shadow stroke.
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(3.5)
        ctx.setLineDash(phase: dashPhase, lengths: [8, 5])
        ctx.stroke(r)

        // White marching-ants border.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: dashPhase, lengths: [8, 5])
        ctx.stroke(r)

        // Handle knobs.
        ctx.setLineDash(phase: 0, lengths: [])
        let hs = Self.knobS
        for h in Handle.allCases {
            let c = handleCentre(h)
            let sq = CGRect(x: c.x - hs / 2, y: c.y - hs / 2, width: hs, height: hs)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(sq)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sq)
        }
    }
}

// MARK: - Region state (shared between controller and HUD view)

/// Holds the current capture region so the view always reflects any drag-move.
final class RegionState: ObservableObject {
    @Published var rect: CGRect
    init(_ rect: CGRect) { self.rect = rect }
}

// MARK: - Controller

final class CaptureHUDWindowController: NSObject, NSWindowDelegate {
    private var zoneWindow: NSWindow?
    private var hudPanel: NSPanel?
    private var resizeView: ZoneResizeView?   // strong ref to the zone content view

    // Shared region — updated whenever the HUD (and therefore the zone) is dragged.
    private var regionState = RegionState(.zero)
    // Weak ref so we can push live cropRect updates during an active recording.
    private weak var manager: CaptureManager?

    // Fixed offset zone.origin − hud.origin, used to keep zone in sync when HUD is dragged.
    private var hudToZoneOffset = CGVector.zero

    // Shadow padding inside the HUD host view so the shadow never clips to the view edge.
    static let shadowPad: CGFloat = 18
    // Capsule height (without padding).
    static let capsuleH: CGFloat  = 46
    // Total HUD window height = capsule + 2× shadow padding.
    static let hudH: CGFloat      = capsuleH + shadowPad * 2
    static let hudW: CGFloat      = 490

    @discardableResult
    static func show(
        manager: CaptureManager,
        region:  CGRect,
        onDone:  @escaping () -> Void
    ) -> CaptureHUDWindowController {
        let c = CaptureHUDWindowController()
        c.open(manager: manager, region: region, onDone: onDone)
        return c
    }

    private func open(manager: CaptureManager, region: CGRect, onDone: @escaping () -> Void) {
        self.manager     = manager
        self.regionState = RegionState(region)
        let hudW = Self.hudW
        let hudH = Self.hudH

        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: region.midX, y: region.midY))
        } ?? NSScreen.main ?? NSScreen.screens[0]

        // Position HUD centred below the zone, with a small visual gap.
        // The shadow padding means the visible pill is Self.shadowPad pts above window origin.
        var hudX = region.midX - hudW / 2
        let gap:  CGFloat = 6
        // Window y so that top of shadow-pad area sits `gap` below region.minY.
        var hudY = region.minY - hudH - gap + Self.shadowPad
        hudX = max(screen.frame.minX + 6, min(hudX, screen.frame.maxX - hudW - 6))
        // If below screen, flip above the region.
        if hudY < screen.frame.minY + 6 {
            hudY = region.maxY + gap - Self.shadowPad
        }

        let hudOrigin = CGPoint(x: hudX, y: hudY)
        hudToZoneOffset = CGVector(
            dx: region.origin.x - hudOrigin.x,
            dy: region.origin.y - hudOrigin.y
        )

        // 1. Zone border / resize overlay.
        let rv = ZoneResizeView(frame: CGRect(origin: .zero, size: region.size))
        rv.onResize = { [weak self] newScreenRect in
            Task { @MainActor [weak self] in
                self?.applyNewRect(newScreenRect, source: .resize)
            }
        }
        let zw = NSWindow(
            contentRect: region,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        zw.level              = .floating
        zw.isOpaque           = false
        zw.hasShadow          = false
        zw.backgroundColor    = .clear
        zw.ignoresMouseEvents = false         // must receive mouse for resize handles
        zw.collectionBehavior = [.canJoinAllSpaces]
        zw.contentView        = rv
        resizeView            = rv

        // 2. HUD panel.
        let p = NSPanel(
            contentRect: CGRect(x: hudOrigin.x, y: hudOrigin.y, width: hudW, height: hudH),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.level                       = .floating
        p.isOpaque                    = false
        p.hasShadow                   = false   // shadow drawn inside SwiftUI
        p.backgroundColor             = .clear
        p.collectionBehavior          = [.canJoinAllSpaces]
        p.isMovableByWindowBackground = true    // drag pill → zone follows via delegate
        p.delegate                    = self

        p.contentView = TransparentHostingView(rootView: CaptureHUDView(
            manager:     manager,
            regionState: regionState,
            onDismiss:   { [weak self] in self?.close(); onDone() }
        ))

        zw.orderFrontRegardless()
        p.orderFrontRegardless()

        zoneWindow = zw
        hudPanel   = p
    }

    // MARK: Shared rect update — called both from drag (windowDidMove) and resize

    private enum RectSource { case drag, resize }

    @MainActor
    private func applyNewRect(_ newZoneRect: CGRect, source: RectSource) {
        guard let zone = zoneWindow, let hud = hudPanel else { return }

        // Update zone window (resize already did this for .resize; safe to re-apply).
        if source == .drag {
            zone.setFrameOrigin(newZoneRect.origin)
        } else {
            // For resize the zone window frame was already set by ZoneResizeView.
            // Recompute HUD position to stay centred below the new zone size.
            let hudW   = Self.hudW
            let hudH   = Self.hudH
            let gap: CGFloat = 6
            let screen = NSScreen.screens.first {
                $0.frame.contains(CGPoint(x: newZoneRect.midX, y: newZoneRect.midY))
            } ?? NSScreen.main ?? NSScreen.screens[0]

            var newHudX = newZoneRect.midX - hudW / 2
            var newHudY = newZoneRect.minY - hudH - gap + Self.shadowPad
            newHudX = max(screen.frame.minX + 6, min(newHudX, screen.frame.maxX - hudW - 6))
            if newHudY < screen.frame.minY + 6 {
                newHudY = newZoneRect.maxY + gap - Self.shadowPad
            }
            let newHudOrigin = CGPoint(x: newHudX, y: newHudY)
            hud.setFrameOrigin(newHudOrigin)
            hudToZoneOffset = CGVector(
                dx: newZoneRect.origin.x - newHudOrigin.x,
                dy: newZoneRect.origin.y - newHudOrigin.y
            )
        }

        regionState.rect = newZoneRect
        if manager?.isCapturing == true {
            Task { await self.manager?.updateCropRect(newZoneRect) }
        }
    }

    // MARK: NSWindowDelegate — keep zone in sync when HUD is dragged

    func windowDidMove(_ notification: Notification) {
        guard let hud = hudPanel, let zone = zoneWindow else { return }
        let newOrigin = CGPoint(
            x: hud.frame.origin.x + hudToZoneOffset.dx,
            y: hud.frame.origin.y + hudToZoneOffset.dy
        )
        let newRect = CGRect(origin: newOrigin, size: regionState.rect.size)
        applyNewRect(newRect, source: .drag)
        zone.setFrameOrigin(newOrigin)  // ensure zone tracks immediately
    }

    func close() {
        zoneWindow?.orderOut(nil)
        hudPanel?.orderOut(nil)
        zoneWindow  = nil
        hudPanel    = nil
        resizeView  = nil
    }
}

// MARK: - HUD SwiftUI View

struct CaptureHUDView: View {
    @ObservedObject var manager: CaptureManager
    @ObservedObject var regionState: RegionState
    let onDismiss: () -> Void

    @State private var fps                = 15
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var hasStartedRecording = false

    private let availableFPS = [5, 10, 15, 20, 30]
    private let pad = CaptureHUDWindowController.shadowPad

    var body: some View {
        ZStack {
            if manager.isCapturing {
                recordingContent
            } else {
                idleContent
            }
        }
        // Inner horizontal padding for the pill contents.
        .padding(.horizontal, 14)
        .frame(height: CaptureHUDWindowController.capsuleH)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .shadow(color: .black.opacity(0.38), radius: 14, x: 0, y: 5)
        // Outer padding gives the shadow room so it never clips to the window edge.
        .padding(CaptureHUDWindowController.shadowPad)
        .onChange(of: manager.isCapturing) { capturing in
            if capturing {
                elapsed = 0
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak manager] _ in
                    Task { @MainActor in elapsed = manager?.elapsedSeconds ?? elapsed }
                }
            } else {
                timer?.invalidate(); timer = nil
                if hasStartedRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onDismiss() }
                }
            }
        }
    }

    // MARK: Idle

    private var idleContent: some View {
        HStack(spacing: 8) {
            // Size badge
            HStack(spacing: 4) {
                Image(systemName: "crop").font(.system(size: 11))
                Text(String(format: "%.0f × %.0f", regionState.rect.width, regionState.rect.height))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.secondary)

            pill_divider

            // FPS selector
            HStack(spacing: 2) {
                Text("FPS").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                ForEach(availableFPS, id: \.self) { f in
                    Button { fps = f } label: {
                        Text("\(f)")
                            .font(.system(size: 11, weight: fps == f ? .bold : .regular))
                            .foregroundColor(fps == f ? .accentColor : .primary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(fps == f
                                        ? Color.accentColor.opacity(0.13)
                                        : Color.clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }

            pill_divider

            // Cursor toggle
            Button { manager.showsCursor.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: manager.showsCursor
                          ? "cursorarrow.rays" : "cursorarrow")
                        .font(.system(size: 12))
                    Text("Cursor")
                        .font(.system(size: 11))
                }
                .foregroundColor(manager.showsCursor ? .accentColor : .secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(manager.showsCursor
                            ? Color.accentColor.opacity(0.12) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(manager.showsCursor ? "Hide cursor in recording" : "Show cursor in recording")

            pill_divider

            // Record
            Button {
                hasStartedRecording = true
                Task { await manager.startCapture(cropRect: regionState.rect, fps: fps) }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().fill(Color.red).frame(width: 6, height: 6))
                    Text("Record").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)

            // Cancel
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Recording

    private var recordingContent: some View {
        HStack(spacing: 8) {
            HUDRecBadge()
            Text(formatTime(elapsed))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            pill_divider

            Image(systemName: "film.stack").font(.system(size: 11)).foregroundColor(.secondary)
            Text("\(manager.frameCount)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Text(liveAvgFPS)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button {
                Task { await manager.stopCapture() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                    Text("Stop").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private var pill_divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 20)
    }

    private var liveAvgFPS: String {
        guard elapsed > 0.5 else { return "-- fps" }
        return String(format: "%.1f fps", Double(manager.frameCount) / elapsed)
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

// MARK: - Blinking REC badge

private struct HUDRecBadge: View {
    @State private var dim = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .opacity(dim ? 0.2 : 1)
                .animation(.easeInOut(duration: 0.65).repeatForever(), value: dim)
            Text("REC").font(.system(size: 12, weight: .bold)).foregroundColor(.red)
        }
        .onAppear { dim = true }
    }
}


