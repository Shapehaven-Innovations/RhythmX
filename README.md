# RhythmX

A private menstrual cycle tracker for iPhone. Log your cycle, tag how you feel, and see your patterns. Everything stays on your device.

**No account. No ads. No tracking. No network access.**

![iOS 18+](https://img.shields.io/badge/iOS-18%2B-5E264F) ![SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%205-E8A5B8) ![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)

---

## Features

- **Insights**: a phase ring with today's moon, average cycle and period length, next-period estimate, and charts for phase timing, tags and cervical mucus.
- **Calendar**: a month grid tinted by phase, with a Today card, predicted period days, and a day panel to add or review tags.
- **Tags**: log symptoms, moods and notes by phase, shown as chips you can edit or remove.
- **Cycles**: start a new cycle from a first day and length, and read the Phase Guide.
- **Past Cycles**: archive finished cycles, search them, edit their tags, and swipe to delete one.
- **Reminders**: optional notifications the day before and the day of your next period.
- **Share**: export selected phases as a calendar (`.ics`) file, only when you choose to.
- **Light and dark mode**: blush in light, deep plum in dark, with a moon for each phase: new, crescent, full, waning.
- **Accessibility**: Dynamic Type up to accessibility sizes, VoiceOver labels, Reduce Motion support.

## Privacy

- Data lives in on-device `UserDefaults` and never leaves the phone unless you share an export.
- No third-party SDKs, analytics, accounts or network calls.
- Ships with a privacy manifest (`PrivacyInfo.xcprivacy`) and is intended for the App Store "Data Not Collected" label.

## Requirements

- iOS 18.0 or newer, iPhone
- Xcode with the iOS 18 SDK
- Swift 5, SwiftUI, Swift Charts

## Build and run

1. Clone this repository.
2. Open `RhythmX.xcodeproj` in Xcode.
3. Select the `RhythmX` scheme and run on an iOS 18+ simulator or device.

First launch shows a three-page onboarding. The last page sets your first cycle and generates its events. You can skip it and start from the **Cycles** tab instead.

## Tests

```sh
xcodebuild test -scheme RhythmX \
  -destination 'platform=iOS Simulator,name=<an installed iOS 18+ simulator>'
```

List installed simulators with `xcrun simctl list devices available`.

## Project layout

```
RhythmX/
  Models/        EventStore, ArchivedDataStore, persistence
  Services/      CycleGenerator, TagParser, CalendarMonthModel, PhaseGuideContent
  Views/         Insights, Calendar, Tags, Cycles, Settings, Onboarding
  Views/Components/  MoonPhaseView, WaveBackground, PhaseRingView, PhaseStrip, CardStyle
  DesignSystem.swift  colors, spacing, shared styles
RhythmXTests/    unit tests
```

## Contributing

Bug reports, ideas and pull requests are welcome.

1. Fork the repo and create a feature branch.
2. Make your change and run the tests.
3. Open a pull request describing what changed and why.

## Reporting issues

Open an issue with the steps to reproduce, your iOS version and device model, and a screenshot if it helps.

## Disclaimer

RhythmX is a tracking tool, not medical advice. Predictions are estimates. Talk to a healthcare professional about health concerns.

## License

Licensed under the [Apache License 2.0](LICENSE).
