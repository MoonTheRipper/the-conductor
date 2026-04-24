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

The current app is a working local MVP for the product direction we agreed on. It already lets us validate:

- chord orbit behavior
- interval orbit behavior
- loop start and loop close gesture semantics
- layer balancing for orchestra-style playback
- UI layout for the performance surface
- live hand-tracking integration shape through Vision and AVFoundation
- Core MIDI routing into Logic through a virtual source and optional direct destination send
- real standalone instrument discovery for AU, VST/VST3, and user-added library folders
- direct standalone Audio Unit playback with one AU assignment per orchestration layer
- sampler-backed playback for playable library folders assigned per layer
- per-layer preset or sample-target selection inside each assigned library folder
- per-layer articulation, register shift, note density, velocity bias, and note-length shaping
- timestamp-accurate loop replay based on captured gesture commits
- manual orchestration trims on top of the auto-generated layer mix
- per-layer bus, pan, reverb, and delay routing in standalone mode
- calibration controls for camera-centered gesture remapping
- multi-track MIDI export for the captured loop phrase, with tempo, clip name, and repeat controls
- richer live hand interpretation from spread, roll, and horizontal motion
- smoothed live downbeat-intent diagnostics for camera-driven transport engagement
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
- playable library-folder hosting through `AVAudioUnitSampler`
- panic/all-notes-off control for standalone playback
- searchable instrument browsing and assign-selected-to-all flow
- indexed sample/library folder summaries and selectable playable targets inside each folder
- per-layer bus and effect routing for richer standalone mixes
- shared performance shaping so standalone playback, Logic MIDI, and exported MIDI all honor the same layer voicing controls

The current loop and control implementation exposes:

- loop capture with recorded event timestamps, interval focus, and dynamics
- restart, pause, and clear transport controls in the app UI
- multi-track standard MIDI file export with one musical track per layer, plus export tempo and repeat metadata controls
- persistent calibration and layer-trim settings through `UserDefaults`

Logic's own internal Library patch browser is not a public automation target, so the product should treat Logic integration and standalone hosting as separate capabilities. Library-folder playback in this app is now handled by sampler loading from the user-indexed folders rather than by controlling Logic's proprietary Library UI.

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

## Post-MVP Expansion Ideas

1. Move the audio/plugin core behind a portable C++ layer for cross-platform builds.
2. Add deeper sampler zoning and articulation switching beyond preset-or-batch loading.
3. Extend standalone hosting past Audio Units into real VST3 instantiation.
