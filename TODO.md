# LoopSnap — TODO

Small, self-contained ideas. Nothing huge — just things that would make the app a bit more useful or polished.

---

## Recording

- [ ] **Show a countdown (3-2-1) before recording starts** — gives you time to move the mouse out of the way
- [ ] **Flash the region border red when recording** — clearer visual cue that capture is active
- [ ] **Auto-stop after N seconds** — optional max duration so you don't accidentally record forever
- [ ] **Pause and resume** — stop accumulating frames temporarily without ending the session
- [ ] **Capture audio indicator** — not recording audio, but at least show whether system audio is playing (useful context)
- [ ] **Remember last used region** — re-use the previous crop rect instead of picking every time

## Editing

- [ ] **Delete a range of frames at once** — currently only single-frame deletion; add multi-select
- [ ] **Duplicate a frame** — useful for adding a static hold at the end of a loop
- [ ] **Crop after recording** — adjust the visible area without re-recording
- [ ] **Reverse playback** — play the GIF backwards (or bounce: forward then back)
- [ ] **Set a global frame delay** — one slider to set the same delay for all frames at once

## Export

- [ ] **Output file size estimate** — show an approximate file size before the user hits export
- [ ] **Copy to clipboard** — export GIF directly to the clipboard instead of saving to disk
- [ ] **Resize on export** — scale output to 50%, 75%, etc. to reduce file size
- [ ] **Last export location memory** — default the save panel to wherever you saved last time
- [ ] **APNG export option** — smaller than GIF, supports 24-bit colour, still widely supported

## UI / UX

- [ ] **Dark / light mode icon** — the app icon and HUD should adapt to the system appearance
- [ ] **Drag the HUD overlay** — let the user reposition the recording border overlay
- [ ] **Show elapsed time in the Dock badge** — quick glance at how long you've been recording
- [ ] **Menu bar presence** — small status item so you can start/stop recording without the main window being focused
- [ ] **Keyboard shortcut to start/stop** — global hotkey (e.g. ⌘⇧R) so you never have to click the button
- [ ] **Tooltip on every button** — helpful for new users

## Code quality

- [ ] **Unit tests for `GifExporter`** — test frame count, delay encoding, and error cases
- [ ] **Unit tests for frame trimming logic** in the timeline
- [ ] **Rename internal target from `ScreenToGif` to `LoopSnap`** throughout `Package.swift`, `bundle_app.sh`, and launch config
- [ ] **Audit `@MainActor` usage** — make sure no UI calls slip through off the main actor
- [ ] **Add `os_log` / `Logger` calls** in capture path for easier debugging

## Distribution

- [ ] **Code sign the `.app`** — needed for smooth Gatekeeper experience on other Macs
- [ ] **Notarize and staple** — required to distribute outside the App Store without quarantine warnings
- [ ] **GitHub Actions CI** — auto-build on every push to confirm the project compiles

---

> These are ideas, not commitments. Pick one, open a PR, and check it off.
