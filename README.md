# The Conductor

`The Conductor` is a native desktop instrument for camera-driven hand conducting, harmonic navigation, and DAW control.

The current scaffold is intentionally biased toward the product direction we agreed on:

- Native macOS shell first
- Logic integration through MIDI bridge mode
- Standalone host mode for playing instruments without opening Logic
- Two-circle interaction model for chord and interval control
- Portable core logic that can later move behind a JUCE-powered host layer for Windows support

## What Is In The Repo Now

- `ConductorCore`: harmonic state, gesture mapping, loop logic, routing models
- `TheConductorApp`: SwiftUI macOS shell with a debug gesture simulator
- Tests for chord mapping, loop capture, and transport muting
- Product and architecture notes in `docs/`

The current app is a high-value scaffold, not the final audio app yet. It already lets us validate:

- chord orbit behavior
- interval orbit behavior
- loop start and loop close gesture semantics
- layer balancing for orchestra-style playback
- UI layout for the performance surface

## Current Product Modes

- `Standalone Host`: the app will host instruments and sample libraries directly
- `Logic Bridge`: the app will emit MIDI/control data to Logic via virtual MIDI

Logic's own internal Library patch browser is not a public automation target, so the product should treat Logic integration and standalone hosting as separate capabilities.

## Run Locally

```bash
swift build --product TheConductorApp
swift run TheConductorApp
```

If you later install the full Xcode app, you can also open the package directly in Xcode for a richer macOS-app workflow.

The package also includes tests under `Tests/`, but the currently active Command Line Tools toolchain on this machine does not expose the standard Swift test modules. Run them after switching to the full Xcode developer directory.

## Near-Term Build Order

1. Replace the debug gesture simulator with a Vision hand-tracking backend on macOS.
2. Add Core MIDI virtual endpoints and a Logic Bridge transport layer.
3. Add AU/VST3 discovery and standalone instrument hosting.
4. Add recording/export of generated MIDI phrases.
5. Move the audio/plugin core behind a portable C++ layer for cross-platform builds.
