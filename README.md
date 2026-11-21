
<img width="400" alt="CleanShot 2026-11-20 at 8 32 21 PM" src="https://github.com/user-attachments/assets/c068d029-ecc8-447b-bde2-0117dee6a0c1" />
<img width="400" alt="CleanShot 2026-11-20 at 8 33 06 PM" src="https://github.com/user-attachments/assets/71f83bbe-eab9-4ced-a4c7-505821f152d0" />

<img width="400" alt="CleanShot 2026-11-20 at 8 30 12 PM" src="https://github.com/user-attachments/assets/92aa8e4a-db97-498c-96e6-4e4575529a0f" />

# Mistfall

Mistfall is a macOS screen saver and standalone app that draws slowly changing patterns of light out of tens of thousands of glowing dots.

## Download

Signed, notarized builds are on the [Releases page](https://github.com/dsomar/Mistfall/releases/latest):

- `Mistfall-App.zip`: the standalone app. It can also install the screen saver from its menu.
- `Mistfall-Screensaver.zip`: the screen saver on its own. Unzip it and double-click `Mistfall.saver`.

## What is here

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
