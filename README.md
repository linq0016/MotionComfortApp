# MotionComfort

MotionComfort is an iOS 26 passenger-comfort app prototype built around a stable session shell:

- A visual route: `Minimal`, `Dynamic`, or `Live View`
- A motion input route: `Real-time Motion` or `Demo Motion`
- An audio route: `Off`, `Monotone`, or `Melodic`

The project is intentionally split into small modules so the app shell, motion input, visual rendering, and audio playback can evolve independently.

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

## Current Product Status

- `Minimal`: current primary visual mode
- `Live View`: real camera preview with edge flow overlays
- `Dynamic`: dedicated placeholder route for a future visual mode
- `Monotone`: continuous 100 Hz comfort signal
- `Melodic`: bundled looped music asset

## Module Layout

- `App`: SwiftUI pages, routing, interface orientation observation, and session start/stop flow
- `Core`: shared motion model and small math helpers
- `Visual`: motion input, visual mode routing, minimal flow, live-view camera support, and direction mapping
- `Audio`: audio mode routing and bundled / generated playback assets
- `docs`: product framing, research notes, and safety limits

## Session Flow

1. Open `Dashboard`
2. Choose a visual mode first
3. Choose motion input
4. Choose audio mode
5. Start the fullscreen session
6. Exit back to the dashboard and stop motion / audio together

## Product Positioning

The visual system remains the strongest part of the prototype because it aligns with the same broad design direction Apple uses in Vehicle Motion Cues: animated peripheral indicators that help passengers reconcile visual and vestibular input.

Audio should still be framed conservatively. This is a comfort or support app, not a medical device or guaranteed therapy.

## Immediate Next Steps

1. Replace the `Dynamic` placeholder with its real visual route.
2. Add onboarding and clearer passenger-only safety guidance.
3. Add user studies for visual comfort, audio preference, and false-positive motion cases.
4. Continue tightening session architecture as more visual modes are added.

## Release Versioning

- Keep `project.yml`'s `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` aligned with the current git tag.
- When saving a new `vX.Y.Z` release, bump the app version in the same change so the bundle version and git tag stay in sync.
