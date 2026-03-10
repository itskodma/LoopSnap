import SwiftUI
import AppKit

// MARK: - Window Controller

final class TimelineEditorWindowController: NSObject, NSWindowDelegate {
    // Strong reference — controller stays alive as long as the window is open.
    private static var shared: TimelineEditorWindowController?
    private var window: NSWindow?
    // Keep NSHostingController alive — it owns the SwiftUI lifecycle (onDisappear,
    // @StateObject teardown). NSHostingView alone does not propagate these reliably.
    private var hostingController: NSHostingController<TimelineEditorView>?

    static func open(manager: CaptureManager) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let wc = TimelineEditorWindowController()
        wc.makeWindow(manager: manager)
        shared = wc
    }

    private func makeWindow(manager: CaptureManager) {
        let hc = NSHostingController(rootView: TimelineEditorView(manager: manager))
        hostingController = hc

        let win = NSWindow(contentViewController: hc)
        win.title   = "Timeline Editor"
        win.minSize = NSSize(width: 640, height: 420)
        win.setContentSize(NSSize(width: 960, height: 620))
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func windowWillClose(_ notification: Notification) {
        // Tear down SwiftUI tree synchronously before AppKit finishes the close.
        // Setting hostingController to nil releases the NSHostingController which
        // properly calls onDisappear and releases all @StateObjects (inc. PlaybackController).
        window?.delegate          = nil
        window?.contentViewController = nil
        hostingController         = nil
        window                    = nil
        DispatchQueue.main.async {
            TimelineEditorWindowController.shared = nil
        }
    }
}

// MARK: - Playback controller (class so deinit reliably kills the timer)

@MainActor
private final class PlaybackController: ObservableObject {
    @Published var isPlaying: Bool   = false
    @Published var fps:       Double = 15
    /// Incremented each tick; the view observes this to advance the frame.
    @Published private(set) var tick: Int = 0

    private var timer: Timer?
    // Block-based observer token — does NOT require NSObject or #selector.
    private var closeObserver: (any NSObjectProtocol)?

    init() {
        // Belt-and-suspenders: stop the timer the moment any window signals it
        // will close. onDisappear is not reliably called by NSHostingView.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        reschedule()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func setFPS(_ newFPS: Double) {
        fps = newFPS
        if isPlaying { reschedule() }
    }

    private func reschedule() {
        timer?.invalidate()
        // Weak capture — if the controller is released while the timer is
        // still pending, the closure safely becomes a no-op.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    deinit {
        if let obs = closeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        timer?.invalidate()
    }
}

// MARK: - Annotation model

enum DrawTool: String, CaseIterable, Identifiable {
    case pen   = "pencil"
    case arrow = "arrow.up.right"
    case text  = "textformat"
    case eraser = "eraser"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pen:    return "Pen"
        case .arrow:  return "Arrow"
        case .text:   return "Text"
        case .eraser: return "Eraser"
        }
    }
}

struct Stroke {
    var points:      [CGPoint]
    var color:       NSColor
    var lineWidth:   CGFloat
    var isEraser:    Bool
}

struct TextAnnotation: Identifiable {
    var id        = UUID()
    var text:     String
    var position: CGPoint   // normalised 0–1
    var color:    NSColor
    var fontSize: CGFloat
}

struct FrameAnnotation {
    var strokes:  [Stroke]        = []
    var texts:    [TextAnnotation] = []
}

@MainActor
final class AnnotationStore: ObservableObject {
    @Published var annotations: [Int: FrameAnnotation] = [:]

    func annotation(for index: Int) -> FrameAnnotation {
        annotations[index] ?? FrameAnnotation()
    }

    func addStroke(_ stroke: Stroke, to index: Int) {
        annotations[index, default: FrameAnnotation()].strokes.append(stroke)
    }

    func addText(_ t: TextAnnotation, to index: Int) {
        annotations[index, default: FrameAnnotation()].texts.append(t)
    }

    func removeText(id: UUID, from index: Int) {
        annotations[index]?.texts.removeAll { $0.id == id }
    }

    func undoLast(from index: Int) {
        if !(annotations[index]?.strokes.isEmpty ?? true) {
            annotations[index]?.strokes.removeLast()
        } else {
            annotations[index]?.texts.removeLast()
        }
    }

    func clear(index: Int) {
        annotations[index] = nil
    }

    func clearAll() {
        annotations.removeAll()
    }

    /// Flatten annotations onto a CGImage, returning a new CGImage.
    func rendered(image: CGImage, annotation: FrameAnnotation, size: CGSize) -> CGImage {
        let w = Int(size.width)
        let h = Int(size.height)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }

        // Draw base image (CGContext origin is bottom-left; flip to match NSView/AppKit)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.restoreGState()

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        // Strokes
        for stroke in annotation.strokes {
            guard stroke.points.count > 1 else { continue }
            let path = NSBezierPath()
            path.lineWidth    = stroke.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if stroke.isEraser {
                NSColor.black.setStroke()  // visual only; real eraser in canvas
            } else {
                stroke.color.setStroke()
            }
            let first = denorm(stroke.points[0], in: size)
            path.move(to: first)
            for p in stroke.points.dropFirst() {
                path.line(to: denorm(p, in: size))
            }
            path.stroke()
        }

        // Text annotations
        for t in annotation.texts {
            let pos   = denorm(t.position, in: size)
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.systemFont(ofSize: t.fontSize, weight: .semibold),
                .foregroundColor: t.color,
                .strokeColor:     NSColor.black,
                .strokeWidth:     -2.0
            ]
            let str = NSAttributedString(string: t.text, attributes: attrs)
            str.draw(at: CGPoint(x: pos.x, y: pos.y - t.fontSize))
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage() ?? image
    }

    private func denorm(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}

// MARK: - Annotation canvas (AppKit NSView overlaid on the preview image)

final class AnnotationCanvasView: NSView {
    // Tool state passed in from SwiftUI
    var tool:        DrawTool  = .pen
    var strokeColor: NSColor   = .red
    var strokeWidth: CGFloat   = 3
    // Normalised image rect inside the view (letterboxed .fit display)
    var imageRect: CGRect = .zero
    // Callbacks
    var onStrokeFinished: ((Stroke) -> Void)?
    var onArrowFinished:  ((Stroke) -> Void)?
    var onTextDropped:    ((CGPoint) -> Void)?   // normalised position

    // Current in-progress stroke
    private var currentPoints: [CGPoint] = []
    private var arrowStart: CGPoint?
    private var arrowEnd:   CGPoint?

    // Committed strokes rendered for display only (truth lives in store)
    var displayStrokes:  [Stroke]          = []
    var displayTexts:    [TextAnnotation]  = []

    override var isFlipped: Bool { true }
    override var isOpaque:  Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func normPt(_ viewPt: CGPoint) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let x = (viewPt.x - imageRect.minX) / imageRect.width
        let y = (viewPt.y - imageRect.minY) / imageRect.height
        return CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    override func mouseDown(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        switch tool {
        case .pen, .eraser: currentPoints = [normPt(pt)]
        case .arrow:        arrowStart = normPt(pt); arrowEnd = normPt(pt)
        case .text:
            onTextDropped?(normPt(pt))
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        switch tool {
        case .pen, .eraser:
            currentPoints.append(normPt(pt))
            needsDisplay = true
        case .arrow:
            arrowEnd = normPt(pt)
            needsDisplay = true
        case .text: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        switch tool {
        case .pen:
            guard currentPoints.count > 1 else { currentPoints = []; return }
            let s = Stroke(points: currentPoints, color: strokeColor,
                           lineWidth: strokeWidth, isEraser: false)
            onStrokeFinished?(s)
            currentPoints = []
        case .eraser:
            guard currentPoints.count > 1 else { currentPoints = []; return }
            let s = Stroke(points: currentPoints, color: .black,
                           lineWidth: strokeWidth * 3, isEraser: true)
            onStrokeFinished?(s)
            currentPoints = []
        case .arrow:
            if let s = arrowStart, let e2 = arrowEnd {
                let stroke = Stroke(points: [s, e2], color: strokeColor,
                                    lineWidth: strokeWidth, isEraser: false)
                onArrowFinished?(stroke)
            }
            arrowStart = nil; arrowEnd = nil
        case .text: break
        }
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let allStrokes = displayStrokes + (currentPoints.count > 1
            ? [Stroke(points: currentPoints, color: strokeColor,
                      lineWidth: strokeWidth, isEraser: tool == .eraser)]
            : [])

        for stroke in allStrokes {
            guard stroke.points.count > 1 else { continue }
            let path = NSBezierPath()
            path.lineWidth     = stroke.lineWidth
            path.lineCapStyle  = .round
            path.lineJoinStyle = .round
            if stroke.isEraser {
                NSColor.white.withAlphaComponent(0.85).setStroke()
            } else {
                stroke.color.setStroke()
            }
            let p0 = denorm(stroke.points[0])
            path.move(to: p0)
            for p in stroke.points.dropFirst() { path.line(to: denorm(p)) }
            path.stroke()
        }

        // Arrow preview
        if tool == .arrow, let s = arrowStart, let e2 = arrowEnd {
            drawArrow(from: denorm(s), to: denorm(e2), color: strokeColor,
                      width: strokeWidth, ctx: ctx)
        }
        // Committed arrows stored as 2-point strokes — draw as arrows
        for stroke in displayStrokes where stroke.points.count == 2 {
            // Already drawn above for pen, but arrow detection: skip (we rely on
            // separate arrow strokes not being re-drawn as lines — simplification)
        }

        // Text overlays (positions only — text rendered by SwiftUI layer)
        // Nothing to draw here; SwiftUI Text overlays handle it.
    }

    private func denorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + p.x * imageRect.width,
                y: imageRect.minY + p.y * imageRect.height)
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint,
                           color: NSColor, width: CGFloat, ctx: CGContext) {
        let path = NSBezierPath()
        path.lineWidth     = width
        path.lineCapStyle  = .round
        color.setStroke()
        path.move(to: a); path.line(to: b); path.stroke()

        // Arrowhead
        let angle = atan2(b.y - a.y, b.x - a.x)
        let headLen: CGFloat = max(10, width * 4)
        let spread:  CGFloat = .pi / 6
        let p1 = CGPoint(x: b.x - headLen * cos(angle - spread),
                         y: b.y - headLen * sin(angle - spread))
        let p2 = CGPoint(x: b.x - headLen * cos(angle + spread),
                         y: b.y - headLen * sin(angle + spread))
        let head = NSBezierPath()
        head.lineWidth = width; head.lineCapStyle = .round
        color.setStroke()
        head.move(to: b); head.line(to: p1); head.stroke()
        let head2 = NSBezierPath()
        head2.lineWidth = width; head2.lineCapStyle = .round
        head2.move(to: b); head2.line(to: p2); head2.stroke()
    }
}

// MARK: - Canvas SwiftUI wrapper

struct AnnotationCanvasViewRep: NSViewRepresentable {
    var tool:        DrawTool
    var color:       Color
    var strokeWidth: CGFloat
    var imageRect:   CGRect
    var strokes:     [Stroke]
    var texts:       [TextAnnotation]
    var onStroke:    (Stroke) -> Void
    var onText:      (CGPoint) -> Void

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let v = AnnotationCanvasView()
        v.onStrokeFinished = { onStroke($0) }
        v.onArrowFinished  = { onStroke($0) }
        v.onTextDropped    = { onText($0) }
        return v
    }

    func updateNSView(_ v: AnnotationCanvasView, context: Context) {
        v.tool         = tool
        v.strokeColor  = NSColor(color)
        v.strokeWidth  = strokeWidth
        v.imageRect    = imageRect
        v.displayStrokes = strokes
        v.displayTexts   = texts
        v.needsDisplay   = true
    }
}

// MARK: - Editor View

struct TimelineEditorView: View {
    @ObservedObject var manager: CaptureManager

    @State private var selectedIndex: Int = 0
    @State private var deletedIndices     = Set<Int>()
    @StateObject private var playback     = PlaybackController()
    @StateObject private var annotStore   = AnnotationStore()
    @State private var isExporting        = false
    @State private var exportStatus       = ""

    // Drawing tool state
    @State private var activeTool:   DrawTool = .pen
    @State private var drawColor:    Color    = .red
    @State private var strokeWidth:  CGFloat  = 3
    @State private var showDrawing:  Bool     = false
    // Text input
    @State private var pendingTextPos: CGPoint? = nil
    @State private var textInput:  String = ""
    @State private var textFontSize: CGFloat = 20
    // Image rect inside the preview view (for hit-test normalisation)
    @State private var previewImageRect: CGRect = .zero

    private let thumbW: CGFloat = 112
    private let thumbH: CGFloat = 72
    private let thumbGap: CGFloat = 6

    // Visible (non-deleted) frames in order.
    private var activeFrames: [(index: Int, image: CGImage)] {
        manager.gifFrames.enumerated().compactMap { i, img in
            deletedIndices.contains(i) ? nil : (i, img)
        }
    }

    // Active-frame position of selectedIndex (for playback advance).
    private var activePosition: Int {
        activeFrames.firstIndex(where: { $0.index == selectedIndex }) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                largePreview
                    .frame(minWidth: 320)
                timelinePanel
                    .frame(minWidth: 180, maxWidth: 300)
            }
            Divider()
            // ── Playback strip ──
            playbackBar
            Divider()
            statusBar
        }
        .onAppear  { selectedIndex = manager.gifFrames.indices.first ?? 0 }
        .onDisappear { playback.stop() }        // Text annotation popup
        .sheet(isPresented: Binding(
            get: { pendingTextPos != nil },
            set: { if !$0 { pendingTextPos = nil; textInput = "" } }
        )) {
            VStack(spacing: 14) {
                Text("Add Text").font(.headline)
                TextField("Enter text", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Text("Size").font(.caption).foregroundColor(.secondary)
                    Slider(value: $textFontSize, in: 10...64, step: 1)
                    Text("\(Int(textFontSize))pt").font(.caption.monospaced())
                }
                .frame(width: 260)
                ColorPicker("Color", selection: $drawColor)
                    .frame(width: 260)
                HStack {
                    Button("Cancel") { pendingTextPos = nil; textInput = "" }
                    Spacer()
                    Button("Add") {
                        if let pos = pendingTextPos, !textInput.isEmpty {
                            let t = TextAnnotation(
                                text: textInput, position: pos,
                                color: NSColor(drawColor), fontSize: textFontSize
                            )
                            annotStore.addText(t, to: selectedIndex)
                        }
                        pendingTextPos = nil; textInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(textInput.isEmpty)
                }
                .frame(width: 260)
            }
            .padding(20)
        }        .onChange(of: manager.gifFrames.count) { _ in
            if !manager.gifFrames.indices.contains(selectedIndex) {
                selectedIndex = max(0, manager.gifFrames.count - 1)
            }
        }
        // Timer ticks arrive here; advance the frame index safely.
        .onChange(of: playback.tick) { _ in
            guard playback.isPlaying else { return }
            stepForward()
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("\(activeFrames.count) of \(manager.gifFrames.count) frames")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
            Button {
                deletedIndices.removeAll()
            } label: {
                Label("Restore All", systemImage: "arrow.uturn.backward")
            }
            .disabled(deletedIndices.isEmpty)

            Divider().frame(height: 20)

            // Drawing toggle
            Group {
                if showDrawing {
                    Button {
                        showDrawing.toggle()
                        if !showDrawing { playback.stop() }
                    } label: {
                        Label("Hide Drawing", systemImage: "pencil.slash")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        showDrawing.toggle()
                    } label: {
                        Label("Draw", systemImage: "pencil.and.scribble")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider().frame(height: 20)

            Button { exportGif() } label: {
                Label(isExporting ? "Exporting…" : "Export GIF",
                      systemImage: isExporting ? "hourglass" : "square.and.arrow.up")
            }
            .disabled(activeFrames.isEmpty || isExporting || manager.isCapturing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Large preview

    private var largePreview: some View {
        VStack(spacing: 0) {
            // Drawing toolbar (shown only when draw mode is active)
            if showDrawing {
                drawingToolbar
                Divider()
            }
            ZStack {
                Color.black
                Group {
                    let img: CGImage? = {
                        if manager.gifFrames.indices.contains(selectedIndex),
                           !deletedIndices.contains(selectedIndex) {
                            return manager.gifFrames[selectedIndex]
                        }
                        return activeFrames.first?.image
                    }()
                    if let img {
                        GeometryReader { geo in
                            let fitted = fittedRect(image: img, in: geo.size)
                            ZStack(alignment: .topLeading) {
                                Image(decorative: img, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                if showDrawing {
                                    let ann = annotStore.annotation(for: selectedIndex)
                                    // Text overlays positioned on the image
                                    ForEach(ann.texts) { t in
                                        Text(t.text)
                                            .font(.system(size: t.fontSize, weight: .semibold))
                                            .foregroundColor(Color(t.color))
                                            .shadow(color: .black, radius: 1, x: 1, y: 1)
                                            .position(
                                                x: fitted.minX + t.position.x * fitted.width,
                                                y: fitted.minY + t.position.y * fitted.height
                                            )
                                            .contextMenu {
                                                Button("Remove") {
                                                    annotStore.removeText(id: t.id, from: selectedIndex)
                                                }
                                            }
                                    }

                                    AnnotationCanvasViewRep(
                                        tool:        activeTool,
                                        color:       drawColor,
                                        strokeWidth: strokeWidth,
                                        imageRect:   fitted,
                                        strokes:     ann.strokes,
                                        texts:       ann.texts,
                                        onStroke: { stroke in
                                            annotStore.addStroke(stroke, to: selectedIndex)
                                        },
                                        onText: { pos in
                                            pendingTextPos = pos
                                        }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .onAppear { previewImageRect = fitted }
                            .onChange(of: geo.size) { _ in previewImageRect = fitted }
                        }
                    } else {
                        Text("No frames").foregroundColor(.secondary)
                    }
                }
                // Frame counter badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Frame \(selectedIndex + 1) / \(manager.gifFrames.count)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
            }
        }
    }

    /// Returns the rect (in the GeometryReader's coordinate space) that the
    /// .fit image actually occupies, accounting for aspect-ratio letterboxing.
    private func fittedRect(image: CGImage, in size: CGSize) -> CGRect {
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        guard iw > 0, ih > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / iw, size.height / ih)
        let fw    = iw * scale
        let fh    = ih * scale
        return CGRect(x: (size.width  - fw) / 2,
                      y: (size.height - fh) / 2,
                      width: fw, height: fh)
    }

    // MARK: Drawing toolbar

    @ViewBuilder
    private var drawingToolbar: some View {
        HStack(spacing: 6) {
            // Tool picker
            ForEach(DrawTool.allCases) { tool in
                Button {
                    activeTool = tool
                } label: {
                    Label(tool.label, systemImage: tool.rawValue)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(activeTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(activeTool == tool ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .help(tool.label)
            }

            Divider().frame(height: 20)

            // Colour picker
            ColorPicker("", selection: $drawColor)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .help("Stroke / text colour")

            // Stroke width
            Text("W")
                .font(.caption).foregroundColor(.secondary)
            Slider(value: $strokeWidth, in: 1...20, step: 0.5)
                .frame(width: 80)
            Text(String(format: "%.0fpt", strokeWidth))
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 32)

            Divider().frame(height: 20)

            // Undo / Clear
            Button {
                annotStore.undoLast(from: selectedIndex)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(annotStore.annotation(for: selectedIndex).strokes.isEmpty
                      && annotStore.annotation(for: selectedIndex).texts.isEmpty)
            .help("Undo last")

            Button {
                annotStore.clear(index: selectedIndex)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Clear this frame")

            Button {
                annotStore.clearAll()
            } label: {
                Label("Clear All", systemImage: "trash.slash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Clear all frames")

            Spacer()

            Text("Drawing mode")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Playback bar

    private var playbackBar: some View {
        HStack(spacing: 16) {
            // ← first frame
            Button { jumpTo(0) } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(activeFrames.isEmpty)

            // ← prev frame
            Button { stepBack() } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.plain)
            .disabled(activeFrames.isEmpty)

            // Play / Pause
            Button { playback.isPlaying ? playback.stop() : startPlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(activeFrames.isEmpty)
            .keyboardShortcut(.space, modifiers: [])  // set modifier to [] to avoid conflicting with text fields

            // → next frame
            Button { stepForward() } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.plain)
            .disabled(activeFrames.isEmpty)

            // → last frame
            Button { jumpTo(activeFrames.count - 1) } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(activeFrames.isEmpty)

            Divider().frame(height: 18)

            // FPS slider
            Text("Speed")
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: playFPSBinding, in: 1...60, step: 1)
                .frame(width: 100)
            Text("\(Int(playback.fps)) fps")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Spacer()

            // Progress text
            Text(activeFrames.isEmpty ? "—" :
                 "\(activePosition + 1) / \(activeFrames.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var playFPSBinding: Binding<Double> {
        Binding(
            get: { playback.fps },
            set: { playback.setFPS($0) }
        )
    }

    // MARK: Timeline panel (right side, scrollable thumbnail strip)

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            Text("Timeline")
                .font(.caption).foregroundColor(.secondary)
                .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: thumbGap) {
                        ForEach(manager.gifFrames.indices, id: \.self) { i in
                            frameCell(index: i).id(i)
                        }
                    }
                    .padding(thumbGap)
                }
                .onChange(of: selectedIndex) { idx in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func frameCell(index: Int) -> some View {
        let isDeleted  = deletedIndices.contains(index)
        let isSelected = selectedIndex == index

        ZStack(alignment: .topTrailing) {
            Image(decorative: manager.gifFrames[index], scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbW, height: thumbH)
                .clipped()
                .cornerRadius(5)
                .opacity(isDeleted ? 0.22 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )

            Text("\(index + 1)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 3).padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(3)

            if isDeleted {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .frame(width: thumbW, height: thumbH)
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = index }
        .contextMenu {
            if isDeleted {
                Button("Restore Frame") { deletedIndices.remove(index) }
            } else {
                Button("Delete Frame") { deletedIndices.insert(index) }
            }
            Divider()
            Button("Go to Frame") { selectedIndex = index }
        }
        .help(isDeleted
              ? "Frame \(index+1) — marked for deletion (right-click to restore)"
              : "Frame \(index+1)")
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            Text(exportStatus.isEmpty
                 ? "\(manager.gifFrames.count) total  ·  \(deletedIndices.count) deleted  ·  \(activeFrames.count) will export"
                 : exportStatus)
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    // MARK: Playback logic

    private func startPlayback() {
        guard !activeFrames.isEmpty else { return }
        playback.start()
    }

    private func stepForward() {
        guard !activeFrames.isEmpty else { return }
        let next = (activePosition + 1) % activeFrames.count
        selectedIndex = activeFrames[next].index
    }

    private func stepBack() {
        guard !activeFrames.isEmpty else { return }
        let prev = (activePosition - 1 + activeFrames.count) % activeFrames.count
        selectedIndex = activeFrames[prev].index
    }

    private func jumpTo(_ position: Int) {
        guard activeFrames.indices.contains(position) else { return }
        selectedIndex = activeFrames[position].index
    }

    // MARK: Export

    private func exportGif() {
        playback.stop()
        // Bake annotations onto every active frame before encoding
        let frames: [CGImage] = activeFrames.map { (idx, img) in
            let ann = annotStore.annotation(for: idx)
            guard !ann.strokes.isEmpty || !ann.texts.isEmpty else { return img }
            let sz = CGSize(width: img.width, height: img.height)
            return annotStore.rendered(image: img, annotation: ann, size: sz)
        }
        guard !frames.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.gif]
        panel.nameFieldStringValue = "recording.gif"
        panel.title                = "Export Timeline as GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting  = true
        exportStatus = "Exporting \(frames.count) frames…"

        Task {
            do {
                let delay = 1.0 / Double(manager.capturedFPS)
                try await Task.detached(priority: .userInitiated) {
                    try GifExporter.export(frames: frames, delaySeconds: delay, to: url)
                }.value
                exportStatus = "Exported \(frames.count) frames → \(url.lastPathComponent)"
            } catch {
                exportStatus = "Export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}

