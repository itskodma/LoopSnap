import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RecorderView: View {
    @StateObject private var manager = CaptureManager()
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var selectedRegion: CGRect?
    // Hold strong refs so ARC doesn't tear them down mid-flow.
    @State private var picker: RegionPickerWindowController?
    @State private var hud: CaptureHUDWindowController?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 16) {
            previewArea
            statsRow
            statusText
            regionLabel
            controlButton
            HStack(spacing: 12) {
                exportButton
                editorButton
            }
        }
        .padding(16)
        .frame(width: 420)
        .onChange(of: manager.isCapturing) { capturing in
            if capturing {
                elapsed = 0
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak manager] _ in
                    Task { @MainActor in
                        elapsed = manager?.elapsedSeconds ?? elapsed
                    }
                }
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    // MARK: - Sub-views

    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.88))
                .aspectRatio(16 / 9, contentMode: .fit)

            if let image = manager.previewImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.25))
                    Text("No preview")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            // REC badge — top-right corner while recording
            if manager.isCapturing {
                VStack {
                    HStack {
                        Spacer()
                        RecBadge().padding(10)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsRow: some View {
        HStack(spacing: 32) {
            statCell(
                value: manager.isCapturing ? formatTime(elapsed) : "--:--",
                label: "Duration"
            )
            statCell(value: "\(manager.frameCount)", label: "Frames")
            statCell(
                value: manager.isCapturing && elapsed > 0
                    ? String(format: "%.0f", Double(manager.frameCount) / elapsed)
                    : "--",
                label: "FPS"
            )
        }
    }

    private var statusText: some View {
        Text(manager.statusMessage)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }

    // Always the same height — shows a placeholder when no area is selected
    // so the window layout doesn't shift when a region is picked or cleared.
    private var regionLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "crop").font(.caption)
            if let r = selectedRegion {
                Text(String(format: "%.0f × %.0f  at (%.0f, %.0f)", r.width, r.height, r.minX, r.minY))
                    .font(.caption)
                Button {
                    selectedRegion = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("No area selected").font(.caption)
            }
        }
        .foregroundColor(.secondary)
        .opacity(selectedRegion != nil ? 1 : 0.35)
    }

    private var exportButton: some View {
        Button { exportGif() } label: {
            Label(
                isExporting ? "Exporting\u{2026}" : "Export GIF",
                systemImage: isExporting ? "hourglass" : "square.and.arrow.up"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!manager.hasRecording || isExporting || manager.isCapturing)
    }

    private var editorButton: some View {
        Button {
            TimelineEditorWindowController.open(manager: manager)
        } label: {
            Label("Editor", systemImage: "film.stack")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!manager.hasRecording || manager.isCapturing)
    }

    private var controlButton: some View {
        Button {
            if manager.isCapturing {
                Task { await manager.stopCapture() }
            } else {
                startPickerThenRecord()
            }
        } label: {
            Label(
                manager.isCapturing ? "Stop Recording" : "Select Area & Record",
                systemImage: manager.isCapturing ? "stop.circle.fill" : "record.circle"
            )
            .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .tint(manager.isCapturing ? .red : .accentColor)
        .controlSize(.large)
        .keyboardShortcut(.space, modifiers: [])
    }

    // MARK: - Region picker flow

    private func startPickerThenRecord() {
        manager.statusMessage = "Drag to select area…"
        // Capture the window ref NOW — after orderOut, NSApp.keyWindow is nil.
        let recorderWindow = NSApp.keyWindow
        recorderWindow?.orderOut(nil)

        let p = RegionPickerWindowController()
        picker = p
        p.show { [self, manager, recorderWindow] rect in
            picker = nil
            guard let rect else {
                manager.statusMessage = "Cancelled"
                recorderWindow?.makeKeyAndOrderFront(nil)
                return
            }
            selectedRegion = rect
            // Show the floating HUD — it owns Record/Stop from here.
            // The recorder window is restored when the HUD dismisses.
            hud = CaptureHUDWindowController.show(
                manager: manager,
                region:  rect,
                onDone: {
                    hud = nil
                    recorderWindow?.makeKeyAndOrderFront(nil)
                }
            )
        }
    }

    // MARK: - GIF export

    private func exportGif() {
        let frames = manager.gifFrames
        guard !frames.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.gif]
        panel.nameFieldStringValue = "recording.gif"
        panel.title                = "Export Recording as GIF"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting           = true
        manager.statusMessage = "Exporting \(frames.count) frames…"

        // Run the (potentially slow) ImageIO encoding on a background thread.
        Task {
            do {
                let delay = 1.0 / Double(manager.capturedFPS)
                try await Task.detached(priority: .userInitiated) {
                    try GifExporter.export(frames: frames, delaySeconds: delay, to: url)
                }.value
                manager.statusMessage = "Exported \(frames.count) frames → \(url.lastPathComponent)"
            } catch {
                manager.statusMessage = "Export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    // MARK: - Helpers

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 64)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - REC Badge

private struct RecBadge: View {
    @State private var dim = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(dim ? 0.25 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(), value: dim)
            Text("REC")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .onAppear { dim = true }
    }
}

