# Product Spec

## Core Experience

The user conducts harmony with two hands in front of a camera.

- Right hand drives the harmonic destination and ensemble energy.
- Left hand shapes interval focus, voicing, and orchestration color.
- The system interprets gestures continuously but only commits harmonic changes on explicit intent.

## MVP Interaction Grammar

### Right Hand

- position on chord circle: choose harmonic destination
- pinch: commit the current preview chord
- open + fast downward motion: engage the ensemble
- closed + pinch: mute / stop the ensemble

### Left Hand

- position on interval circle: choose interval emphasis
- radius from center: change orchestration density

### Two-Hand Gesture

- both hands pinched: toggle loop capture

Loop behavior:

- first toggle starts recording
- second toggle closes the loop and starts playback
- third toggle clears the loop
- when Logic Bridge mode is active, loop playback is emitted back to MIDI channels
- loop playback should preserve the recorded event timing rather than flattening the phrase

## Harmony Engine Goals

- stay diatonic by default
- support borrowed colors around the circle
- maintain musically sensible orchestration layers
- keep room for exported MIDI and DAW handoff

## Standalone Sound Sources

- discover installed Audio Units
- host discovered Audio Unit instruments directly inside the app
- allow separate AU assignments for `Strings`, `Brass`, `Woods`, and `Pulse`
- discover installed VST/VST3 bundles from standard plugin folders
- allow user-added library folders for sample sources
- load playable library folders through a sampler when audio or supported preset assets are present
- expose per-layer preset or sample-target selection inside each assigned library folder
- expose per-layer articulation, register, density, and note-length controls for orchestration shaping
- keep the selected target visible in the main control surface
- label non-hostable targets clearly so discovery and playback status are not conflated
- expose searchable catalog browsing so large plugin installs stay manageable
- expose per-layer output bus and effect controls inside the same performance surface
- allow export-time clip naming, tempo choice, and repeat count without leaving the surface

## Visual Language

- large performance surface
- chord orbit and interval orbit as distinct circles
- visible current marker, not just labels
- current chord, interval, loop state, and layer mix visible at a glance
- layer trims, loop transport, and calibration controls exposed without leaving the main surface
- standalone routing and effect controls visible without opening a secondary editor
- per-layer performance shaping visible without opening a secondary editor
- saved scene recall visible without leaving the main surface
- live beat-intent diagnostics visible while tuning the camera path

## Post-MVP Directions

1. Move the standalone host/audio core toward a portable layer for cross-platform builds.
2. Add deeper sampler zoning and articulation switching for large orchestral libraries.
3. Extend standalone hosting beyond Audio Units into real VST3 instantiation.
