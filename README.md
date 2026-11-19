# Mistfall

Mistfall is a macOS screen saver and standalone app that draws slowly changing patterns of light out of tens of thousands of glowing dots.

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
