# Sus-o-meter

A camera-and-voice party game for iPhone, built for the DEV Presage Challenge (`#presagechallenge`).
One player sits in the hot seat, friends ask questions out loud, and the app reads live pulse,
blinks, expressions and hesitation with the Presage SmartSpectra SDK, then gives a game-show
verdict: **Legit / Hmm… / Sus!**

> **It reads stress, not truth.** This is an entertainment game. It is not a lie detector and not a
> medical device.

Work in progress. The design and build spec is in [`docs/SPEC.md`](docs/SPEC.md). Full setup
instructions arrive with milestone 6.

## Quick start (developers)

Requirements: a Mac with Xcode 26 or later, an iPhone on iOS 17+, Flutter 3.38+ (tested with
3.47.9), and a Presage API key from [physiology.presagetech.com](https://physiology.presagetech.com).

```bash
flutter pub get
flutter run        # with your iPhone connected
```

On first launch, open Settings (gear icon) and paste your Presage API key. It is stored in the
iPhone's Keychain and never committed to this repo.
