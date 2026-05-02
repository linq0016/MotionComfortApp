<img width="120" height="120" alt="Screenshot 2026-04-20 at 10 48 10" src="https://github.com/user-attachments/assets/392b76e9-f4d9-4cea-8004-71b0e7460c9f" />
Stellar目前已经上架iOS App Store，可以搜索全名或点击链接：
https://apps.apple.com/cn/app/stellar-motion-comfort/id6762748536?l

Stellar仍在积极维护更新，最新版本请见TestFlight公测链接：
https://testflight.apple.com/join/WsDpa9ah

# Stellar: The Motion Comfort App 晕动缓解视听体验
Stellar是我个人用OpenAI Codex从0开发的一款专门用来缓解乘坐机动车时容易产生的晕动症的App，目前项目文件为完全开源。

Stellar的灵感来自于，因为我的女朋友乘坐网约车常常受到晕车的困扰，我也希望以较有效且较注重美学体验的方式来缓解她的这种烦恼。Stellar也是我为晕动症这一受害者广泛的生活烦恼所做的解决方案，目前支持三种视觉模式（极简、星际巡航、实况视窗）以随着加速度变化的粒子特效来使惯性力可视化，辅以两种可选择的听觉模式（一种为纯100Hz正弦波，另一种为基于G2=100Hz调音的原创G大调乐曲，着重强调了G2=100Hz的根音）通过播放100Hz的声波来刺激耳石系统。这两种手段都被过往科研证实对人类及其他动物的晕动症有较明显的缓解。相对于已研究过的类似竞品，Stellar致力于提供一种足够有趣、美观且令人愉悦的视听体验，来保证这两种手段的持续作用，目标是将其基础功能和用户体验打磨到极致；相对于iOS自带的晕动症缓解辅助功能，它又能以一个独立App的形式确保用户接受这种反直觉的体验（即，已经晕车感到不适了，却需要继续看手机来缓解，但的确只有持续接受这些视觉和听觉的刺激超过1分钟才能有所好转）。


以下为自动生成的项目详细介绍
# Stellar

Stellar is an iOS motion comfort app designed to help ease motion sickness during travel. It combines real-time motion-responsive visual guidance with optional 100 Hz-based audio modes, creating a lightweight local experience for passengers in cars, planes, boats, and similar environments.

## What It Does

Stellar provides three visual modes:

- **Minimal**: clean peripheral dot guidance that responds to device motion.
- **Interstellar**: an immersive star-field view with motion-reactive particles and adjustable cruise speed.
- **Live View**: a camera-based viewfinder with calming edge effects, so users can still see the real world.

The app also includes optional audio modes, background audio support, quick startup, and local-only settings persistence.

## How It Works

Motion sickness is commonly associated with sensory conflict between visual input, vestibular signals, and body motion cues. Stellar uses the device motion sensor to visualize acceleration through stable, predictable visual patterns. These cues are intended to reduce the mismatch between what users feel and what they see.

Audio modes are based around 100 Hz sound stimulation, which some research suggests may help modulate the inner ear system for certain users. Effects may vary by individual.

Stellar is not a medical product and does not provide medical advice.

## Privacy

Stellar is fully local. It does not require an internet connection and does not collect or upload health data, location data, audio, or usage history.

The app uses:

- Motion sensor data for core visual guidance.
- Camera access only for Live View mode.
- Local storage only for user preferences.

## Code Structure

- `App/` — SwiftUI app shell, dashboard, onboarding, settings, fullscreen session UI, and haptics.
- `Core/` — shared motion data models and core types.
- `Visual/` — motion processing, Minimal / Live View dot rendering, Interstellar Metal renderer, and camera support.
- `Audio/` — 100 Hz-based audio engine and bundled melodic audio asset.
- `project.yml` — project generation/configuration source.
- `App/Resources/` — localized strings and Info.plist localization.

## Platform

Stellar currently targets iOS 26 and uses Liquid Glass APIs for its interface.

## Release Versioning

- Keep `project.yml`'s `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` aligned with the current git tag.
- When saving a new `vX.Y.Z` release, bump the app version in the same change so the bundle version and git tag stay in sync.
