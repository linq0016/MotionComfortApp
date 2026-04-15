# Research And Safety Notes

## Evidence Summary

- Apple ships `Vehicle Motion Cues` on iPhone, which uses animated dots on screen edges to help reduce motion sickness for passengers. This is the clearest product signal that peripheral visual guidance is a reasonable direction.
- `CMMotionManager` provides the motion data needed to drive a passenger-comfort overlay in real time.
- Auditory mitigation is much less settled. Research exists around anticipatory cueing and a recent 100 Hz stimulation paper, but the evidence is not strong enough to justify treatment language.

## Product Claims Boundary

Use language like:

- "reduce discomfort"
- "support comfort during travel"
- "assist with motion adaptation"

Avoid language like:

- "treats motion sickness"
- "relaxes the cochlea"
- "medical therapy"
- "clinically proven"

## Safety Constraints

- Passenger-only use. Never encourage use while driving.
- Default audio volume should stay conservative.
- The app should tell users to stop immediately if audio causes pressure, tinnitus, headache, or worse nausea.
- Consider adding a "visual only" preset as the default onboarding path.

## Sources

- Apple Support, Vehicle Motion Cues:
  [https://support.apple.com/en-kw/guide/iphone/iph55564cb22/ios](https://support.apple.com/en-kw/guide/iphone/iph55564cb22/ios)
- Apple Developer Documentation, CMMotionManager:
  [https://developer.apple.com/documentation/coremotion/cmmotionmanager](https://developer.apple.com/documentation/coremotion/cmmotionmanager)
- Environmental Health and Preventive Medicine, 100 Hz sound study:
  [https://pmc.ncbi.nlm.nih.gov/articles/PMC11955832/](https://pmc.ncbi.nlm.nih.gov/articles/PMC11955832/)
- Review touching multisensory cueing strategies for motion sickness:
  [https://pmc.ncbi.nlm.nih.gov/articles/PMC7602081/](https://pmc.ncbi.nlm.nih.gov/articles/PMC7602081/)
