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
- `TheConductorApp`: SwiftUI macOS shell with simulator/live tracking, a Logic Bridge panel, and a standalone AU host
- Tests for chord mapping, loop capture, and transport muting
- Product and architecture notes in `docs/`

The current app is a high-value scaffold, not the final audio app yet. It already lets us validate:

- chord orbit behavior
- interval orbit behavior
- loop start and loop close gesture semantics
- layer balancing for orchestra-style playback
- UI layout for the performance surface
- live hand-tracking integration shape through Vision and AVFoundation
- Core MIDI routing into Logic through a virtual source and optional direct destination send
- real standalone instrument discovery for AU, VST/VST3, and user-added library folders
- direct standalone Audio Unit playback with one AU assignment per orchestration layer
- timestamp-accurate loop replay based on captured gesture commits
- manual orchestration trims on top of the auto-generated layer mix
- calibration controls for camera-centered gesture remapping
- MIDI export for the captured loop phrase
- searchable instrument catalog and indexed library-folder summaries

## Current Product Modes

- `Standalone Host`: the app will host instruments and sample libraries directly
- `Logic Bridge`: the app will emit MIDI/control data to Logic via virtual MIDI

The current Logic Bridge implementation exposes:

- a virtual MIDI source named `The Conductor`
- direct destination selection for endpoints such as `Logic Pro Virtual In`
- layer-to-channel mapping for `Strings`, `Brass`, `Woods`, and `Pulse`
- loop playback routing back into MIDI when a progression is closed

The current standalone catalog implementation exposes:

- Audio Unit instrument discovery through the system component manager
- VST/VST3 discovery from standard macOS plugin folders
- user-added sample/library folders inside the app UI
- live target selection from the discovered catalog
- per-layer Audio Unit hosting for discovered AU instrument entries
- panic/all-notes-off control for standalone playback
- searchable instrument browsing and assign-selected-to-all flow
- indexed sample/library folder summaries so future sample hosting has useful source context

The current loop and control implementation exposes:

- loop capture with recorded event timestamps, interval focus, and dynamics
- restart, pause, and clear transport controls in the app UI
- standard MIDI file export for the current loop
- persistent calibration and layer-trim settings through `UserDefaults`

Logic's own internal Library patch browser is not a public automation target, so the product should treat Logic integration and standalone hosting as separate capabilities.

## Run Locally

```bash
swift test
swift build --product TheConductorApp
swift run TheConductorApp
```

If you later install the full Xcode app, you can also open the package directly in Xcode for a richer macOS-app workflow.

If the active developer directory still points to the standalone Command Line Tools, switch it permanently with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## Near-Term Build Order

1. Tighten live hand gesture extraction beyond wrist-position tracking.
2. Add richer live gesture inference for hand openness, orientation, and beat intent.
3. Add sample-library playback behind the indexed library folders.
4. Add multi-track MIDI export with reusable tempo/clip metadata.
5. Move the audio/plugin core behind a portable C++ layer for cross-platform builds.
