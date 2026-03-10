# LoopSnap

A native macOS screen-to-GIF recorder built with Swift and SwiftUI.

LoopSnap was born out of necessity. [ScreenToGif](https://www.screentogif.com/) is a fantastic Windows-only tool — and when switching to macOS means losing access to it, you build your own. LoopSnap is not a port or a clone; it is a fresh, macOS-native reimagining of the same core workflow: draw a region, record it, trim it in a timeline, and export a looping GIF.

Have an idea or want to pick something up? See [TODO.md](TODO.md) for a list of small, self-contained improvements.

---

## Features

- **Region capture** — drag to select any area of any display before recording
- **Live preview** — see the last captured frame in real time inside the recorder window
- **HUD overlay** — a frameless, click-through overlay sits above the selected region while recording
- **Timeline editor** — scrub through every frame, delete unwanted ones, and preview playback before export
- **GIF export** — single-click export via `ImageIO`; GPU-accelerated frame processing via `CoreImage`
- **Cursor capture** — toggle whether the system cursor is included in the recording
- **Adjustable FPS** — choose the capture frame rate before you start
- **macOS 13+ native** — built on `ScreenCaptureKit`, SwiftUI, and Swift Package Manager; no third-party dependencies

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13 Ventura or later |
| Xcode / Swift toolchain | Swift 5.9+ |
| Screen Recording permission | granted in System Settings → Privacy & Security |

---

## Getting Started

### Clone

```bash
git clone https://github.com/your-username/loopsnap.git
cd loopsnap
```

### Run in development

```bash
swift run
```

### Build a standalone `.app` bundle

```bash
chmod +x bundle_app.sh
./bundle_app.sh
open LoopSnap.app
```

> **First launch:** macOS will prompt for Screen Recording permission. Grant it in  
> System Settings → Privacy & Security → Screen Recording, then relaunch the app.

---

## Project Structure

```
loopsnap/
├── Package.swift                        # Swift Package Manager manifest
├── bundle_app.sh                        # Script to produce a .app bundle
├── Sources/
│   └── LoopSnap/                            # Main target
│       ├── main.swift                   # App entry point & NSApplication bootstrap
│       ├── RecorderView.swift           # Main recorder window (SwiftUI)
│       ├── CaptureManager.swift         # ScreenCaptureKit capture logic
│       ├── GifExporter.swift            # ImageIO GIF encoding
│       ├── TimelineEditorView.swift     # Frame scrubbing & trimming UI
│       ├── RegionPickerWindowController.swift  # Full-screen region selection overlay
│       ├── CaptureHUDWindowController.swift    # Recording HUD overlay
│       └── Resources/
│           └── AppIcon.icns
└── AppIcon.iconset/                     # Source icon assets
```

---

## Contributing

Contributions are welcome and appreciated. Here is how to get involved.

### Reporting bugs

1. Search [existing issues](../../issues) first — the bug may already be reported.
2. Open a new issue and include:
   - macOS version (`sw_vers`)
   - Steps to reproduce (be specific — region size, FPS, display count, etc.)
   - What you expected vs. what happened
   - Console output from **Console.app** or `log stream` if there is a crash

### Requesting features

Open a [feature request issue](../../issues/new) describing the problem you want solved, not just the solution you have in mind. This makes it easier to find the best approach together.

### Submitting code

1. **Fork** the repository and create a branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Follow the code style** already in use:
   - Swift API Design Guidelines naming
   - `// MARK: -` sections to group related logic
   - `@MainActor` on all UI-touching classes and methods
   - No third-party dependencies — stay within Apple frameworks

3. **Keep commits focused.** One logical change per commit. Write commit messages in the imperative mood: `Add frame delay slider` not `Added frame delay slider`.

4. **Test your change** manually:
   - Record a short clip and verify GIF output
   - Test with multiple displays if your change touches display/region logic
   - Confirm the app launches cleanly from both `swift run` and the `.app` bundle

5. **Open a Pull Request** against `main`:
   - Describe what the PR does and why
   - Reference any related issues (e.g. `Closes #12`)
   - Include a screen recording or screenshot if the change is visual

### Areas that need help

| Area | Notes |
|---|---|
| Code signing & notarization | The `.app` bundle is currently ad-hoc; proper signing would allow distribution |
| APNG / WebP export | GIF is the current output format; APNG and WebP would reduce file size significantly |
| Frame delay editor | Per-frame delay control in the timeline editor |
| Retina / HiDPI handling | Verify correct pixel density on all supported display configurations |
| Keyboard shortcuts | Standard macOS shortcuts for record/stop, export, and timeline navigation |
| Unit tests | `GifExporter` and `CaptureManager` have no test coverage yet |

---

## Releases

Pre-built `.app` bundles are published on the [GitHub Releases page](../../releases). Each release includes:

- A zipped `.app` bundle ready to drag into `/Applications`
- A changelog describing what changed since the previous version
- The minimum macOS version required

To build from source instead, see [Getting Started](#getting-started).

---

## License

LoopSnap is released under the [MIT License](LICENSE).

You are free to use, modify, and distribute this software. If you publish a fork or a derivative work, **you must credit the original author** — in source code headers, documentation, or an about screen, wherever is most visible. See [LICENSE](LICENSE) for the full terms.

> **A note from the author:** This is my first Swift project. The code has rough edges and I know it. If you see something that could be done better — architecturally, idiomatically, or for performance — please open an issue or PR and tell me. Criticism is genuinely welcome here.

---

## Acknowledgements

Inspired by [ScreenToGif](https://www.screentogif.com/) by Nicke Manarin — the best screen-to-GIF tool on Windows. This project would not exist without it.
