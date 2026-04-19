import MotionComfortCore
import Testing

struct CueStateTests {
    @Test
    func neutralSampleProducesNeutralCue() {
        let cue = CueState.from(sample: .neutral)

        #expect(cue.lateralOffset == 0.0)
        #expect(cue.longitudinalOffset == 0.0)
        #expect(cue.horizonTilt == 0.0)
    }

    @Test
    func lateralAccelerationIncreasesSeverityAndOffset() {
        let sample = MotionSample(
            timestamp: 1.0,
            lateralAcceleration: 0.35,
            longitudinalAcceleration: 0.12,
            verticalAcceleration: 0.0,
            pitch: 0.0,
            roll: 0.18,
            yawRate: 0.55
        )

        let cue = CueState.from(sample: sample)

        #expect(cue.lateralOffset > 0.0)
        #expect(cue.severity > 0.0)
        #expect(cue.glowOpacity > 0.28)
    }
}
