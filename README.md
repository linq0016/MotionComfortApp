# MotionComfort

MotionComfort is an iOS 26 starter project for an anti-motion-sickness app built around two ideas:

- Peripheral visual cues driven by live motion sensing.
- Optional comfort audio modes, including an experimental 100 Hz low-tone mode.

The project is intentionally split into small modules so the visual, audio, and motion logic can evolve independently.

## Why XcodeGen

`XcodeGen` is not required to build this product, but it is a useful project-management tool:

- It keeps the project structure in `project.yml` instead of a hand-edited `.xcodeproj`.
- It makes multi-target setups easier to review in Git.
- It reduces drift when the app grows into separate modules.

If you want to use it, run:

```bash
brew install xcodegen
xcodegen generate
open MotionComfort.xcodeproj
```

If you prefer a standard Xcode app template instead, the source layout in this repository can still be copied into a manually created project.

## Module Layout

- `App`: SwiftUI app shell and session orchestration.
- `Core`: motion models, smoothing, cue math, and layout engine.
- `Visual`: Core Motion ingestion and the peripheral guide overlay.
- `Audio`: comfort audio modes and loop generation.
- `docs`: product framing, research notes, and safety limits.

## Product Positioning

The visual system is the strongest part of the MVP because it aligns with the same broad design direction Apple uses in Vehicle Motion Cues: animated peripheral indicators that help passengers reconcile visual and vestibular input.

The audio system should be framed more carefully:

- `Adaptive Drone` is a comfort sound mode.
- `Experimental 100 Hz` is an experiment setting, not a treatment claim.

This should be positioned as a comfort or support app, not as a medical device or guaranteed therapy.

## Immediate Next Steps

1. Add a host app icon, launch treatment, and onboarding flow.
2. Add orientation-aware calibration for portrait and landscape phone placement.
3. Add user studies for severity scoring, volume preference, and false-positive motion cases.
4. Add Health and Safety review copy before any public release.
