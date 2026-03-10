import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import AppKit

// Shared GPU-accelerated CIContext — thread-safe for concurrent rendering calls.
private let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

@MainActor
final class CaptureManager: NSObject, ObservableObject {
    @Published var isCapturing    = false
    @Published var statusMessage  = "Ready to record"
    @Published var frameCount     = 0
    @Published var previewImage: CGImage?
    /// True after a recording has been stopped and frames are available to export.
    @Published var hasRecording   = false
    /// Raw frames accumulated during capture for GIF export.
    private(set) var gifFrames: [CGImage] = []

    private var stream: SCStream?
    private var captureStartDate: Date?

    // Computed on the main actor; safe to read from the view.
    var elapsedSeconds: TimeInterval {
        captureStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    // MARK: - Public API

    /// FPS used for the last/current capture — used when exporting GIF.
    @Published private(set) var capturedFPS: Int = 15

    /// Whether to capture the system cursor in the recording.
    @Published var showsCursor: Bool = true

    /// `cropRect` is in global NSScreen coordinates (origin bottom-left).
    /// Pass `nil` to capture the full primary display.
    func startCapture(cropRect: CGRect?, fps: Int = 15) async {
        guard !isCapturing else { return }
        statusMessage = "Starting…"

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            // Find the display that contains the (center of the) crop rect.
            let display: SCDisplay
            if let crop = cropRect,
               let match = content.displays.first(where: {
                   displayContains($0, point: CGPoint(x: crop.midX, y: crop.midY))
               }) {
                display = match
            } else if let first = content.displays.first {
                display = first
            } else {
                statusMessage = "No display found"
                return
            }

            // Convert cropRect from NSScreen global coords → display-local points.
            // NSScreen has origin bottom-left; SCStream sourceRect uses the same space
            // but relative to the display's own frame (i.e., subtract display origin).
            let displayFrame = frameForDisplay(display)   // in NSScreen coords
            let sourceRect: CGRect
            if let crop = cropRect {
                // Clamp to display bounds
                let clamped = crop.intersection(displayFrame)
                sourceRect = CGRect(
                    x: clamped.minX - displayFrame.minX,
                    y: clamped.minY - displayFrame.minY,
                    width:  clamped.width,
                    height: clamped.height
                )
            } else {
                sourceRect = CGRect(origin: .zero, size: displayFrame.size)
            }

            let config = SCStreamConfiguration()
            // Output pixel dimensions = logical pts × backing scale factor
            let scale = backingScaleForDisplay(display)
            config.width          = Int(sourceRect.width  * scale)
            config.height         = Int(sourceRect.height * scale)
            config.sourceRect     = sourceRect
            capturedFPS = fps
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.queueDepth     = 5
            config.showsCursor    = showsCursor

            // Exclude our own process so the HUD pill and zone-border overlay
            // never appear in the recording.
            let ourPID       = ProcessInfo.processInfo.processIdentifier
            let excludedApps = content.applications.filter { $0.processID == ourPID }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )

            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: .global(qos: .userInitiated)
            )
            try await stream?.startCapture()

            isCapturing      = true
            frameCount       = 0
            gifFrames        = []
            hasRecording     = false
            captureStartDate = Date()
            statusMessage    = "Recording…"
        } catch {
            stream        = nil
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    /// Re-crops a running stream to a new rect (global NSScreen coordinates).
    /// No-op if not currently capturing. Failures are silently ignored.
    func updateCropRect(_ cropRect: CGRect) async {
        guard isCapturing, let stream else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                displayContains($0, point: CGPoint(x: cropRect.midX, y: cropRect.midY))
            }) else { return }

            let displayFrame = frameForDisplay(display)
            let clamped      = cropRect.intersection(displayFrame)
            let sourceRect   = CGRect(
                x: clamped.minX - displayFrame.minX,
                y: clamped.minY - displayFrame.minY,
                width:  clamped.width,
                height: clamped.height
            )
            let config  = SCStreamConfiguration()
            let scale   = backingScaleForDisplay(display)
            config.width  = Int(sourceRect.width  * scale)
            config.height = Int(sourceRect.height * scale)
            config.sourceRect            = sourceRect
            config.minimumFrameInterval  = CMTime(value: 1, timescale: CMTimeScale(capturedFPS))
            config.queueDepth            = 5
            config.showsCursor           = showsCursor
            let ourPID       = ProcessInfo.processInfo.processIdentifier
            let excludedApps = content.applications.filter { $0.processID == ourPID }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )
            try await stream.updateConfiguration(config)
            try await stream.updateContentFilter(filter)
        } catch {
            // Non-fatal: keep recording with the previous region.
        }
    }

    func stopCapture() async {
        guard isCapturing else { return }

        // Attempt graceful stop; ignore errors in the prototype.
        try? await stream?.stopCapture()

        let duration = captureStartDate.map { Date().timeIntervalSince($0) } ?? 0
        stream           = nil
        isCapturing      = false
        captureStartDate = nil

        let avgFPS = duration > 0 ? Double(frameCount) / duration : 0
        hasRecording  = !gifFrames.isEmpty
        statusMessage = String(
            format: "Stopped — %d frames, %.1f fps avg",
            frameCount, avgFPS
        )
    }

    // MARK: - Display helpers

    private func displayContains(_ display: SCDisplay, point: CGPoint) -> Bool {
        frameForDisplay(display).contains(point)
    }

    /// Returns the NSScreen-space frame for a given SCDisplay.
    private func frameForDisplay(_ display: SCDisplay) -> CGRect {
        // Match SCDisplay to NSScreen by comparing dimensions as a best-effort heuristic.
        // SCDisplay.frame is in points, same coordinate space as NSScreen.frame.
        if let screen = NSScreen.screens.first(where: {
            Int($0.frame.width)  == display.width &&
            Int($0.frame.height) == display.height
        }) {
            return screen.frame
        }
        // Fallback: assume display origin is zero.
        return CGRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    private func backingScaleForDisplay(_ display: SCDisplay) -> CGFloat {
        if let screen = NSScreen.screens.first(where: {
            Int($0.frame.width) == display.width && Int($0.frame.height) == display.height
        }) {
            return screen.backingScaleFactor
        }
        return 2.0
    }
}

// MARK: - SCStreamOutput

extension CaptureManager: SCStreamOutput {
    /// Called on `sampleHandlerQueue` (background) — must NOT touch main-actor state directly.
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        // Preview thumbnail — 320 pt wide, built on background thread.
        let thumbScale = 320.0 / ciImage.extent.width
        let thumbCi    = ciImage.transformed(by: CGAffineTransform(scaleX: thumbScale, y: thumbScale))
        let thumbnail  = sharedCIContext.createCGImage(thumbCi, from: thumbCi.extent)

        // GIF frame — 480 pt wide max, every frame, built on background thread.
        let gifScale = min(1.0, 480.0 / ciImage.extent.width)
        let gifCi    = ciImage.transformed(by: CGAffineTransform(scaleX: gifScale, y: gifScale))
        let gifFrame = sharedCIContext.createCGImage(gifCi, from: gifCi.extent)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.frameCount += 1
            // Refresh preview every 3rd frame to avoid overwhelming the main thread.
            if self.frameCount % 3 == 0, let thumbnail {
                self.previewImage = thumbnail
            }
            if let gifFrame {
                self.gifFrames.append(gifFrame)
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension CaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCapturing  = false
            self.stream       = nil
            self.statusMessage = "Stream stopped: \(error.localizedDescription)"
        }
    }
}
