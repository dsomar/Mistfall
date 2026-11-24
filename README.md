# Mistfall

**A free, open-source screen saver for the Mac.** About 70,000 glowing dots drift into 17 slowly changing patterns of light, drawn with Metal.

### [Download for Mac (free)](https://github.com/dsomar/Mistfall/releases/latest)

macOS 13 or later · signed and notarized by Apple · no ads, no accounts, no tracking

<img width="400" alt="CleanShot 2026-11-20 at 8 32 21 PM" src="https://github.com/user-attachments/assets/c068d029-ecc8-447b-bde2-0117dee6a0c1" />
<img width="400" alt="CleanShot 2026-11-20 at 8 33 06 PM" src="https://github.com/user-attachments/assets/71f83bbe-eab9-4ced-a4c7-505821f152d0" />

<img width="400" alt="CleanShot 2026-11-20 at 8 30 12 PM" src="https://github.com/user-attachments/assets/92aa8e4a-db97-498c-96e6-4e4575529a0f" />
<img width="400" alt="CleanShot 2026-11-20 at 8 39 04 PM" src="https://github.com/user-attachments/assets/8fcc2c59-e35d-44d9-8acc-0a4cc8b15ce6" />

## Why I made it

Mistfall is a macOS screen saver and standalone app that draws slowly changing patterns of light out of tens of thousands of glowing dots.  It's completely free, signed and notarized by Apple, full source is in this package.  It is made in honor of a screensaver (Snoqualmie by Syntrillium) which fascinated me enough with the beauty of its renders that I wanted to understand imaging and computers more and more, which led me down the rabbit hole of digital design.

<img width="600" alt="image" src="https://github.com/user-attachments/assets/20533f64-3a51-4768-8d24-f8d5a69b37f0" />

## Download

It is available as a screensaver AND a standalone Mac app (so you can tinker with it w/o having to be in screen-saving mode). You can download signed, notarized builds  [on the Releases page](https://github.com/dsomar/Mistfall/releases/latest):

- `Mistfall-App.zip`: the standalone app. It can also install the screen saver from its menu.
- `Mistfall-Screensaver.zip`: the screen saver on its own. Unzip it and double-click `Mistfall.saver`.

## Questions

**What do I need?** A Mac running macOS 13 or later.

**Does it work with more than one display?** Yes. When it starts on its own, Mistfall covers every connected display.

**Can I use it without setting it as my screen saver?** Yes. Open the app and choose "Start When Idle" in the Mistfall menu, with how long to wait. Turn on "Open at Login" and it's always ready.

**How do I remove it?** Delete `Mistfall.saver` from `~/Library/Screen Savers` (or `/Library/Screen Savers` if you installed it for all users), and drag `Mistfall.app` to the Trash.

**Found a bug or have an idea for a pattern?** [Open an issue](https://github.com/dsomar/Mistfall/issues). Pull requests are welcome.

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

Mistfall is open source under the [GNU General Public License v3.0](LICENSE). You may use, change and share it for any purpose, including commercially. If you distribute it or a version based on it, you must do so under the same licence and make the source available.

---

If you enjoy Mistfall, a star on this repo helps other people find it.
