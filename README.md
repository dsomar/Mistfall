
<img width="400" alt="CleanShot 2026-11-20 at 8 32 21 PM" src="https://github.com/user-attachments/assets/c068d029-ecc8-447b-bde2-0117dee6a0c1" />
<img width="400" alt="CleanShot 2026-11-20 at 8 33 06 PM" src="https://github.com/user-attachments/assets/71f83bbe-eab9-4ced-a4c7-505821f152d0" />

<img width="400" alt="CleanShot 2026-11-20 at 8 30 12 PM" src="https://github.com/user-attachments/assets/92aa8e4a-db97-498c-96e6-4e4575529a0f" />
<img width="400" alt="CleanShot 2026-11-20 at 8 39 04 PM" src="https://github.com/user-attachments/assets/8fcc2c59-e35d-44d9-8acc-0a4cc8b15ce6" />


# Mistfall

Mistfall is a macOS screen saver and standalone app that draws slowly changing patterns of light out of tens of thousands of glowing dots.  It's completely free, open-source and is innocuous, but if you don't believe me, download the code and build it yourself with Claude or Codex, and Xcode.  It is made in honor of a screensaver (Snoqualmie by Syntrillium) which fascinated me enough with the beauty of its renders that I wanted to understand imaging and computers more and more, which led me down the rabbit hole of digital design.
<img width="600" alt="image" src="https://github.com/user-attachments/assets/20533f64-3a51-4768-8d24-f8d5a69b37f0" />

## Download

It is available as a screensaver AND a standalone Mac app (so you can tinker with it w/o having to be in screen-saving mode). You can download signed, notarized builds  [on the Releases page](https://github.com/dsomar/Mistfall/releases/latest):

- `Mistfall-App.zip`: the standalone app. It can also install the screen saver from its menu.
- `Mistfall-Screensaver.zip`: the screen saver on its own. Unzip it and double-click `Mistfall.saver`.

## About the Code

- `Mistfall/`: the engine and the standalone Mac app. `Engine.swift` runs the patterns; `Abstract`, `Cipherfall`, `Flow` and `Prism` hold individual pattern families; `GPU.swift` draws with Metal.
- `Saver/`: the screen saver wrapper around the same engine.
- `Store/`: Mac App Store listing text, entitlements and screenshots.
- `tools/`: small helper scripts (icon maker, screen saver test harness).
- `project.yml`: the project definition. The Xcode project is generated from it.
- `release.sh`: builds, signs and notarizes the app and screen saver. It needs your own Developer ID certificate.

## Building

You need macOS 13 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
xcodegen generate
xcodebuild -scheme Mistfall -configuration Release build
```

The `Mistfall` scheme builds the app, which carries the screen saver inside it. `MistfallStore` is the Mac App Store variant.

## License

Copyright 2026 Secret Weapon Design (https://secretweaponlabs.com).

Mistfall is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may use, change and share it for noncommercial purposes. Commercial use, including commercial works based on it, needs a separate licence. Contact Secret Weapon Design through https://secretweaponlabs.com.
