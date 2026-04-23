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
- keep the selected target visible in the main control surface
- label non-hostable targets clearly so discovery and playback status are not conflated
- expose searchable catalog browsing so large plugin installs stay manageable

## Visual Language

- large performance surface
- chord orbit and interval orbit as distinct circles
- visible current marker, not just labels
- current chord, interval, loop state, and layer mix visible at a glance
- layer trims, loop transport, and calibration controls exposed without leaving the main surface

## Next Milestones

1. Tighten the live hand-tracking model so more than wrist position drives harmony.
2. Improve beat-intent detection from the live camera path.
3. Add per-layer effect or bus routing for richer standalone mixes.
4. Add multi-track MIDI export options and clip metadata.
5. Add deeper library mapping controls beyond first-pass sampler loading.
