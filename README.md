<img width="573" height="573" alt="Screenshot 2026-04-20 at 10 48 10" src="https://github.com/user-attachments/assets/392b76e9-f4d9-4cea-8004-71b0e7460c9f" />

# Stellar: The Motion Comfort App 晕动缓解视听体验
Stellar是我个人用OpenAI Codex从0开发的一款专门用来缓解乘坐机动车时容易产生的晕动症的App，目前项目文件为完全开源。
由于时效性与中国大陆的法规要求，苹果App Store上架/TestFlight External Testing正在申请中，目前项目可以Internal Testing的形式运行，但需要联系我手动添加权限。如果有需要，请随时联系我的邮箱linq0016@icloud.com。

Stellar的灵感来自于，因为我的女朋友乘坐网约车常常受到晕车的困扰，我也希望以较有效且较注重美学体验的方式来缓解她的这种烦恼。Stellar也是我为晕动症这一受害者广泛的生活烦恼所做的解决方案，目前支持三种视觉模式（极简、星际巡航、实况视窗）以随着加速度变化的粒子特效来使惯性力可视化，辅以两种可选择的听觉模式（一种为纯100Hz正弦波，另一种为基于G2=100Hz调音的原创G大调乐曲，着重强调了G2=100Hz的根音）通过播放100Hz的声波来刺激耳石系统。这两种手段都被过往科研证实对人类及其他动物的晕动症有较明显的缓解。相对于已研究过的类似竞品，Stellar致力于提供一种足够有趣、美观且令人愉悦的视听体验，来保证这两种手段的持续作用，目标是将其基础功能和用户体验打磨到极致；相对于iOS自带的晕动症缓解辅助功能，它又能以一个独立App的形式确保用户接受这种反直觉的体验（即，已经晕车感到不适了，却需要继续看手机来缓解，但的确只有持续接受这些视觉和听觉的刺激超过1分钟才能有所好转）。


以下为自动生成的项目详细介绍
# MotionComfort

MotionComfort is an iOS 26 passenger-comfort app prototype built around a stable session shell:

- A visual route: `Minimal`, `Dynamic`, or `Live View`
- A motion input route: `Real-time Motion` or `Demo Motion`
- An audio route: `Off`, `Monotone`, or `Melodic`

The project is intentionally split into small modules so the app shell, motion input, visual rendering, and audio playback can evolve independently

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
- `Dynamic`: H5-matched nebula particle starfield with layered clouds, dust, and warp travel
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

1. Tighten the new `Dynamic` route with device-side performance tuning and visual parity checks against the H5 reference.
2. Add onboarding and clearer passenger-only safety guidance.
3. Add user studies for visual comfort, audio preference, and false-positive motion cases.
4. Continue tightening session architecture as more visual modes are added.

## Release Versioning

- Keep `project.yml`'s `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` aligned with the current git tag.
- When saving a new `vX.Y.Z` release, bump the app version in the same change so the bundle version and git tag stay in sync.
