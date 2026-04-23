# Architecture

## Product Shape

The application is designed around two runtime modes:

- `Standalone Host`: host instruments directly, manage layers, render progressions, and loop internally.
- `Logic Bridge`: route generated notes and control data into Logic over virtual MIDI.

That split is deliberate. It avoids coupling the product to undocumented Logic internals while still making Logic a first-class destination.

## Current Layers

### `ConductorCore`

Pure state and musical intent:

- gesture snapshot model
- chord-circle and interval-circle mapping
- loop capture state machine
- orchestration layer balancing
- routing and instrument-catalog abstractions

This layer should remain portable so it can later sit behind a JUCE host or other native shells.

### `TheConductorApp`

Native macOS presentation shell:

- SwiftUI desktop surface
- chord and interval orbit visualization
- routing and instrument selection controls
- debug gesture simulator for deterministic tuning
- Vision + AVFoundation live hand-tracking path
- Core MIDI bridge with virtual source and direct destination routing
- standalone instrument catalog discovery for AU, VST/VST3, and library folders

## Planned Integrations

### Hand Tracking

First macOS backend:

- `Vision`
- `AVFoundation`

Future parity backend:

- `MediaPipe`

### DAW / Audio

macOS first:

- `Core MIDI` virtual sources and destinations
- Audio Unit discovery
- VST/VST3 filesystem discovery
- Audio Unit discovery/hosting
- Logic Bridge layer routing orchestration channels into the DAW

Cross-platform expansion:

- `JUCE` plugin host and audio graph
- VST3 hosting

## Shipping Direction

No paid Apple Developer Program is required for local development, local testing, or GitHub distribution.

The immediate goal is:

- develop locally
- iterate in public on GitHub
- avoid App Store constraints during early host/plugin work
